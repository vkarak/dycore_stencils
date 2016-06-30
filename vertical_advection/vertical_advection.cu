#include "vertical_advection.h"
#include "../repository.hpp"
#include "../utils.hpp"
#include "vertical_advection_reference.hpp"

#define BLOCK_X_SIZE 32
#define BLOCK_Y_SIZE 8

#define HALO_BLOCK_X_MINUS 1
#define HALO_BLOCK_X_PLUS 1

#define HALO_BLOCK_Y_MINUS 1
#define HALO_BLOCK_Y_PLUS 1


#define PADDED_BOUNDARY 1

inline
__device__
unsigned int cache_index(const unsigned int ipos, const unsigned int jpos)
{
    return (ipos+PADDED_BOUNDARY) + (jpos+HALO_BLOCK_Y_MINUS)*(BLOCK_X_SIZE+HALO_BLOCK_X_MINUS+HALO_BLOCK_X_PLUS);
}

template<int IMinusExtent, int IPlusExtent, int JMinusExtent, int JPlusExtent>
__device__
inline bool is_in_domain(const int iblock_pos, const int jblock_pos, const unsigned int block_size_i, const unsigned int block_size_j)
{
    return (iblock_pos >= IMinusExtent && iblock_pos < ((int)block_size_i + IPlusExtent) &&
                  jblock_pos >= JMinusExtent && jblock_pos < ((int)block_size_j + JPlusExtent));
} 


__global__
void cukernel(Real* in, Real* out, Real* coeff, const IJKSize domain, const IJKSize halo, const IJKSize strides)
{

    unsigned int ipos, jpos;
    int iblock_pos, jblock_pos;
    const unsigned int jboundary_limit = BLOCK_Y_SIZE + HALO_BLOCK_Y_MINUS+HALO_BLOCK_Y_PLUS;
    const unsigned int iminus_limit = jboundary_limit + HALO_BLOCK_X_MINUS;
    const unsigned int iplus_limit = iminus_limit + HALO_BLOCK_X_PLUS;

    const unsigned int block_size_i = (blockIdx.x + 1) * BLOCK_X_SIZE < domain.m_i
                                            ? BLOCK_X_SIZE
                                            : domain.m_i - blockIdx.x * BLOCK_X_SIZE;
    const unsigned int block_size_j = (blockIdx.y + 1) * BLOCK_Y_SIZE < domain.m_j
                                            ? BLOCK_Y_SIZE
                                            : domain.m_j - blockIdx.y * BLOCK_Y_SIZE;


    if(threadIdx.y < jboundary_limit ) {
        ipos = blockIdx.x * BLOCK_X_SIZE + threadIdx.x + halo.m_i;
        jpos = blockIdx.y * BLOCK_Y_SIZE + threadIdx.y - HALO_BLOCK_Y_MINUS + halo.m_j;
        iblock_pos = threadIdx.x;
        jblock_pos = threadIdx.y - HALO_BLOCK_Y_MINUS;
    }
    else if( threadIdx.y < iminus_limit)
    {
        ipos = blockIdx.x * BLOCK_X_SIZE - PADDED_BOUNDARY + threadIdx.x % PADDED_BOUNDARY;
        jpos = blockIdx.y * BLOCK_Y_SIZE + threadIdx.x / PADDED_BOUNDARY - HALO_BLOCK_Y_MINUS;
        iblock_pos = -PADDED_BOUNDARY + (int)threadIdx.x % PADDED_BOUNDARY;
        jblock_pos = threadIdx.x / PADDED_BOUNDARY - HALO_BLOCK_Y_MINUS;
    }
    else if( threadIdx.y < iplus_limit)
    {
        ipos = blockIdx.x * BLOCK_X_SIZE + threadIdx.x % PADDED_BOUNDARY +
              BLOCK_X_SIZE;
        jpos = blockIdx.y * BLOCK_Y_SIZE + threadIdx.x / PADDED_BOUNDARY - HALO_BLOCK_Y_MINUS;
        iblock_pos = threadIdx.x % PADDED_BOUNDARY + BLOCK_X_SIZE;
        jblock_pos = threadIdx.x / PADDED_BOUNDARY - BLOCK_Y_SIZE;
    }

    __shared__ Real lap[(BLOCK_X_SIZE+HALO_BLOCK_X_MINUS + HALO_BLOCK_X_PLUS)*(BLOCK_Y_SIZE+2)]; 
    __shared__ Real flx[(BLOCK_X_SIZE+1)*(BLOCK_Y_SIZE)];
    __shared__ Real fly[(BLOCK_X_SIZE)*(BLOCK_Y_SIZE+1)];
   
    
    for(int kpos=0; kpos < domain.m_k; ++kpos)
    {


        if(is_in_domain<-1,1,-1,1>(iblock_pos, jblock_pos, block_size_i, block_size_j) ) {

            lap[ cache_index(iblock_pos, jblock_pos) ] = (Real)4 * in[index(ipos, jpos, kpos, strides)] - ( in[index(ipos+1, jpos, kpos, strides)] + 
                in[index(ipos-1, jpos, kpos, strides)]+in[index(ipos, jpos+1, kpos, strides)]+in[index(ipos, jpos-1, kpos, strides)]);
        }

        __syncthreads();


        if( is_in_domain<-1,0,0,0>(iblock_pos, jblock_pos, block_size_i, block_size_j) ) {
    
            flx[ cache_index(iblock_pos, jblock_pos)] = lap[cache_index(iblock_pos+1, jblock_pos)] - lap[cache_index(iblock_pos, jblock_pos)];
            if ( flx[ cache_index(iblock_pos, jblock_pos)] * (in[index(ipos+1, jpos, kpos, strides)] - in[index(ipos, jpos, kpos, strides)] ) > 0) {
                flx[ cache_index(iblock_pos, jblock_pos)] = 0.;
            }
        }

        __syncthreads();

         if( is_in_domain<0,0,-1,0>(iblock_pos, jblock_pos, block_size_i, block_size_j) ) {
    
            fly[ cache_index(iblock_pos, jblock_pos)] = lap[cache_index(iblock_pos, jblock_pos+1)] - lap[cache_index(iblock_pos, jblock_pos)];
            if ( fly[ cache_index(iblock_pos, jblock_pos)] * (in[index(ipos, jpos+1, kpos, strides)] - in[index(ipos, jpos, kpos, strides)] ) > 0) {
                fly[ cache_index(iblock_pos, jblock_pos)] = 0.;
            }
        }

        __syncthreads();
       
        if( is_in_domain<0,0,0,0>(iblock_pos, jblock_pos, block_size_i, block_size_j) ) {
            out[index(ipos, jpos, kpos, strides)]=in[index(ipos, jpos, kpos, strides)] - coeff[index(ipos, jpos, kpos, strides)] *
                (flx[cache_index(iblock_pos, jblock_pos)]- flx[cache_index(iblock_pos-1, jblock_pos)] + fly[cache_index(iblock_pos, jblock_pos)]- fly[cache_index(iblock_pos, jblock_pos-1)]);
        }

    }

}

void launch_kernel(repository& repo)
{
    IJKSize domain = repo.domain();
    IJKSize halo = repo.halo();

    dim3 threads, blocks;
    threads.x = BLOCK_X_SIZE;
    threads.y = BLOCK_Y_SIZE;
    threads.z = 1;

    blocks.x = (domain.m_i + BLOCK_X_SIZE -1)/ BLOCK_X_SIZE;
    blocks.y = (domain.m_j + BLOCK_Y_SIZE -1)/ BLOCK_Y_SIZE;
    blocks.z = 1;
    if(domain.m_i % 32 != 0 || domain.m_j % 8 != 0)
        std::cout << "ERROR: Domain sizes should be multiple of 32x8" << std::endl;

    IJKSize strides;
    compute_strides(domain, strides);

    Real* in = repo.field_d("u_in");
    Real* out = repo.field_d("u_out");
    Real* coeff = repo.field_d("coeff");
   
    cukernel<<<blocks, threads,0>>>(in, out, coeff, domain, halo, strides);

}
