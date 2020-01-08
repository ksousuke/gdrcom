// Program : rdma_gpu.cu
// Author : Sousuke Kanamoto

#include <cuda.h>
#include "rdma_common.h"

struct ibv_mr *mr = NULL;
int totalsize, buffsize;
void *addr;

/* This function outputs RDMA memory region (called from cpu) */
__global__ void output_host(char *array)
{
	printf("rdma_buffer: '%s'\n",array);
}

/* This function outputs RDMA memory region (called from gpu) */
__device__ void output_device(char *array)
{
	printf("rdma_buffer: '%s'\n",array);
}

/* This function is memcmp (for gpu) */
__device__ int memcompare(const void *s1, const void *s2, size_t n)
{
	register const unsigned char *ss1, *ss2, *t;
	int result = 0;

	for (ss1 = (const unsigned char *)s1, ss2 = (const unsigned char *)s2, t = ss2 + n;
    	ss2 != t && (result = *ss1 - *ss2) == 0;
    	ss1++, ss2++);

	return result;
}

/* This function registers RDMA memory region on GPU */
extern "C" struct ibv_mr* rdma_gpubuffer_alloc(struct ibv_pd *pd, uint32_t length,
    enum ibv_access_flags permission)
{
	if (!pd) {
		rdma_error("Protection domain is NULL \n");
		return NULL;
	}
	cudaMalloc((void**)&addr, length);
	if (!addr) {
		rdma_error("failed to allocate buffer, -ENOMEM\n");
		return NULL;
	}
	debug("Buffer allocated: %p , len: %u \n", addr, length);

	if (!pd) {
		rdma_error("Protection domain is NULL, ignoring \n");
		return NULL;
	}
	mr = ibv_reg_mr(pd, addr, length, permission);
	if (!mr) {
		rdma_error("Failed to create mr on buffer, errno: %d \n", -errno);
		cudaFree(addr);
	}
	debug("Registered: %p , len: %u , stag: 0x%x \n", 
	      mr->addr, 
	      (unsigned int) mr->length, 
	      mr->lkey);

	totalsize = length/sizeof(char); /* Total memory region size (buffsize*2) */
	buffsize = totalsize/2; /* Memory region size (RDMA Write or RDMA Read) */

	return mr;
}

/* This function releases RDMA memory region on GPU */
extern "C" void rdma_gpubuffer_free()
{
        if (!mr) {
	        rdma_error("Passed memory region is NULL, ignoring\n");
		return ;
	}
	void *to_free = mr->addr;

	debug("Deregistered: %p , len: %u , stag : 0x%x \n", 
	      mr->addr, 
	      (unsigned int) mr->length, 
	      mr->lkey);
	ibv_dereg_mr(mr);

	debug("Buffer %p free'ed\n", to_free);
	cudaFree(to_free);
}

/* This function is kernel on GPU */
__global__ void kernel(void *addr, int totalsize, int buffsize)
{
        char src[] = "input", *s = src;
	char dst[] = "output", *d = dst;

	/* Wait RDMA Write and write strings */
	while(1){
	        if(memcompare((void *)addr, (void *)s, 5)==0){ /* Wait RDMA Write */
		        memcpy((void *)addr+buffsize, (const void *)d, 6); /* Write data to RDMA buffer */
			break;
		}
	}
}

/* This function starts kernel on GPU */
extern "C" void kernel_start()
{	
	kernel<<<1, 1>>>(addr, totalsize, buffsize);
}
