/**
 * @file hist.cuh
 * @author Cody Rivera (cjrivera1@crimson.ua.edu), Megan Hickman Fulp (mlhickm@g.clemson.edu)
 * @brief Fast histogramming from [Gómez-Luna et al. 2013]
 * @version 0.1
 * @date 2020-09-20
 * Created on 2020-02-16
 *
 * @copyright (C) 2020 by Washington State University, The University of Alabama, Argonne National Laboratory
 * See LICENSE in top-level directory
 *
 */

#ifndef CUSZ_KERNEL_HIST_CUH
#define CUSZ_KERNEL_HIST_CUH

#include <cuda_runtime.h>
#include <cstdio>
#include <limits>

#include "../common.hh"
#include "../utils/timer.hh"

#define MIN(a, b) ((a) < (b)) ? (a) : (b)
const static unsigned int WARP_SIZE = 32;

#define tix threadIdx.x
#define tiy threadIdx.y
#define tiz threadIdx.z
#define bix blockIdx.x
#define biy blockIdx.y
#define biz blockIdx.z
#define bdx blockDim.x
#define bdy blockDim.y
#define bdz blockDim.z

namespace kernel {

template <typename Input>
__global__ void NaiveHistogram(Input in_data[], int out_freq[], int N, int symbols_per_thread);

/* Copied from J. Gomez-Luna et al */
template <typename Input, typename Output>
__global__ void p2013Histogram(Input*, Output*, size_t, int, int);

}  // namespace kernel

namespace wrapper {
template <typename Input>
void get_frequency(Input* d_in, size_t len, cusz::FREQ* d_freq, int nbin, float& milliseconds);

}  // namespace wrapper

template <typename Input>
__global__ void kernel::NaiveHistogram(Input in_data[], int out_freq[], int N, int symbols_per_thread)
{
    unsigned int i = blockDim.x * blockIdx.x + threadIdx.x;
    unsigned int j;
    if (i * symbols_per_thread < N) {  // if there is a symbol to count,
        for (j = i * symbols_per_thread; j < (i + 1) * symbols_per_thread; j++) {
            if (j < N) {
                unsigned int item = in_data[j];  // Symbol to count
                atomicAdd(&out_freq[item], 1);   // update bin count by 1
            }
        }
    }
}

template <typename Input, typename Output>
__global__ void kernel::p2013Histogram(Input* in_data, Output* out_freq, size_t N, int nbin, int R)
{
    static_assert(
        std::numeric_limits<Input>::is_integer and (not std::numeric_limits<Input>::is_signed),
        "Input Must be Unsigned Integer type of {1,2,4} bytes");

    extern __shared__ int Hs[/*(nbin + 1) * R*/];

    const unsigned int warp_id     = (int)(tix / WARP_SIZE);
    const unsigned int lane        = tix % WARP_SIZE;
    const unsigned int warps_block = bdx / WARP_SIZE;
    const unsigned int off_rep     = (nbin + 1) * (tix % R);
    const unsigned int begin       = (N / warps_block) * warp_id + WARP_SIZE * blockIdx.x + lane;
    unsigned int       end         = (N / warps_block) * (warp_id + 1);
    const unsigned int step        = WARP_SIZE * gridDim.x;

    // final warp handles data outside of the warps_block partitions
    if (warp_id >= warps_block - 1) end = N;

    for (unsigned int pos = tix; pos < (nbin + 1) * R; pos += bdx) Hs[pos] = 0;
    __syncthreads();

    for (unsigned int i = begin; i < end; i += step) {
        int d = in_data[i];
        atomicAdd(&Hs[off_rep + d], 1);
    }
    __syncthreads();

    for (unsigned int pos = tix; pos < nbin; pos += bdx) {
        int sum = 0;
        for (int base = 0; base < (nbin + 1) * R; base += nbin + 1) { sum += Hs[base + pos]; }
        atomicAdd(out_freq + pos, sum);
    }
}

template <typename Input>
void wrapper::get_frequency(Input* d_in, size_t len, cusz::FREQ* d_freq, int nbin, float& milliseconds)
{
    static_assert(
        std::numeric_limits<Input>::is_integer and (not std::numeric_limits<Input>::is_signed),
        "To get frequency, `Input` must be unsigned integer type of {1,2,4} bytes");

    // Parameters for thread and block count optimization
    // Initialize to device-specific values
    int deviceId, max_bytes, max_bytes_opt_in, num_SMs;

    cudaGetDevice(&deviceId);
    cudaDeviceGetAttribute(&max_bytes, cudaDevAttrMaxSharedMemoryPerBlock, deviceId);
    cudaDeviceGetAttribute(&num_SMs, cudaDevAttrMultiProcessorCount, deviceId);

    // Account for opt-in extra shared memory on certain architectures
    cudaDeviceGetAttribute(&max_bytes_opt_in, cudaDevAttrMaxSharedMemoryPerBlockOptin, deviceId);
    max_bytes = std::max(max_bytes, max_bytes_opt_in);

    // Optimize launch
    int num_buckets      = nbin;
    int num_values       = len;
    int items_per_thread = 1;
    int r_per_block      = (max_bytes / (int)sizeof(int)) / (num_buckets + 1);
    int num_blocks       = num_SMs;
    // fits to size
    int threads_per_block = ((((num_values / (num_blocks * items_per_thread)) + 1) / 64) + 1) * 64;
    while (threads_per_block > 1024) {
        if (r_per_block <= 1) { threads_per_block = 1024; }
        else {
            r_per_block /= 2;
            num_blocks *= 2;
            threads_per_block = ((((num_values / (num_blocks * items_per_thread)) + 1) / 64) + 1) * 64;
        }
    }

    cudaFuncSetAttribute(
        kernel::p2013Histogram<Input, cusz::FREQ>, cudaFuncAttributeMaxDynamicSharedMemorySize, max_bytes);

    auto t = new cuda_timer_t;
    t->timer_start();
    kernel::p2013Histogram                                                                    //
        <<<num_blocks, threads_per_block, ((num_buckets + 1) * r_per_block) * sizeof(int)>>>  //
        (d_in, d_freq, num_values, num_buckets, r_per_block);
    milliseconds += t->timer_end_get_elapsed_time();
    cudaDeviceSynchronize();
}

#endif