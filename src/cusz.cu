/**
 * @file cusz.cu
 * @author Jiannan Tian
 * @brief Driver program of cuSZ.
 * @version 0.1
 * @date 2020-09-20
 * Created on 2019-12-30
 *
 * @copyright (C) 2020 by Washington State University, The University of Alabama, Argonne National Laboratory
 * See LICENSE in top-level directory
 *
 */

#include <math.h>
#include <thrust/device_ptr.h>
#include <thrust/extrema.h>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <vector>

using std::string;

#include "analysis/analyzer.hh"
#include "common.hh"
#include "context.hh"
#include "default_path.cuh"
#include "header.hh"
#include "query.hh"
#include "utils.hh"

namespace {

template <typename T>
void check_shell_calls(string cmd_string)
{
    char* cmd = new char[cmd_string.length() + 1];
    strcpy(cmd, cmd_string.c_str());
    int status = system(cmd);
    delete[] cmd;
    cmd = nullptr;
    if (status < 0) { LOGGING(LOG_ERR, "Shell command call failed, exit code: ", errno, "->", strerror(errno)); }
}

}  // namespace

template <typename T, int DownscaleFactor, int tBLK>
T* pre_binning(T* d, size_t* dim_array)
{
    throw std::runtime_error("[pre_binning] disabled temporarily, will be part of preprocessing.");
    return nullptr;
}

#define NONPTR_TYPE(VAR) std::remove_pointer<decltype(VAR)>::type

void normal_path_lorenzo(cuszCTX* ctx)
{
    using T = float;
    using E = ErrCtrlTrait<2>::type;
    using P = FastLowPrecisionTrait<true>::type;

    // TODO be part of the other two tasks without touching FS
    // if (ctx->task_is.experiment) {}

    if (ctx->task_is.construct or ctx->task_is.dryrun) {
        double time_loading{0.0};

        Capsule<T> in_data(ctx->data_len);
        in_data.alloc<cusz::LOC::HOST_DEVICE, cusz::ALIGNDATA::SQUARE_MATRIX>()
            .from_fs_to<cusz::LOC::HOST>(ctx->fnames.path2file, &time_loading)
            .host2device();

        if (ctx->verbose) LOGGING(LOG_DBG, "time loading datum:", time_loading, "sec");
        LOGGING(LOG_INFO, "load", ctx->fnames.path2file, ctx->data_len * sizeof(T), "bytes");

        Capsule<BYTE> out_dump("out dump");

        // TODO This does not cover the output size for *all* predictors.
        if (ctx->on_off.autotune_huffchunk) {
            DefaultPath::DefaultBinding::CODEC::get_coarse_parallelism(
                ctx->data_len, ctx->huffman_chunksize, ctx->nchunk);
        }
        else {
            ctx->nchunk = ConfigHelper::get_npart(ctx->data_len, ctx->huffman_chunksize);
        }

        uint3 xyz{ctx->x, ctx->y, ctx->z};

        if (ctx->huff_bytewidth == 4) {
            DefaultPath::DefaultCompressor cuszc(ctx, &in_data, xyz, ctx->dict_size);

            cuszc  //
                .compress(ctx->on_off.release_input)
                .consolidate<cusz::LOC::HOST, cusz::LOC::HOST>(&out_dump.get<cusz::LOC::HOST>());
            cout << "output:\t" << ctx->fnames.compress_output << '\n';
            out_dump  //
                .to_fs_from<cusz::LOC::HOST>(ctx->fnames.compress_output)
                .free<cusz::LOC::HOST>();
        }
        else if (ctx->huff_bytewidth == 8) {
            DefaultPath::FallbackCompressor cuszc(ctx, &in_data, xyz, ctx->dict_size);

            cuszc  //
                .compress(ctx->on_off.release_input)
                .consolidate<cusz::LOC::HOST, cusz::LOC::HOST>(&out_dump.get<cusz::LOC::HOST>());
            cout << "output:\t" << ctx->fnames.compress_output << '\n';
            out_dump  //
                .to_fs_from<cusz::LOC::HOST>(ctx->fnames.compress_output)
                .free<cusz::LOC::HOST>();
        }
        else {
            throw std::runtime_error("huff nbyte illegal");
        }
        if (ctx->on_off.release_input)
            in_data.free<cusz::LOC::HOST>();
        else
            in_data.free<cusz::LOC::HOST_DEVICE>();
    }

    if (ctx->task_is.reconstruct) {  // fp32 only for now

        auto fname_dump  = ctx->fnames.path2file + ".cusza";
        auto cusza_nbyte = ConfigHelper::get_filesize(fname_dump);

        Capsule<BYTE> in_dump(cusza_nbyte);
        in_dump  //
            .alloc<cusz::LOC::HOST>()
            .from_fs_to<cusz::LOC::HOST>(fname_dump);

        Capsule<T> out_xdata;

        // TODO try_writeback vs out_xdata.to_fs_from()
        if (ctx->huff_bytewidth == 4) {
            DefaultPath::DefaultCompressor cuszd(ctx, &in_dump);

            out_xdata  //
                .set_len(ctx->data_len)
                .alloc<cusz::LOC::HOST_DEVICE, cusz::ALIGNDATA::SQUARE_MATRIX>();
            cuszd  //
                .decompress(&out_xdata)
                .backmatter(&out_xdata);
        }
        else if (ctx->huff_bytewidth == 8) {
            DefaultPath::FallbackCompressor cuszd(ctx, &in_dump);

            out_xdata  //
                .set_len(ctx->data_len)
                .alloc<cusz::LOC::HOST_DEVICE, cusz::ALIGNDATA::SQUARE_MATRIX>();
            cuszd  //
                .decompress(&out_xdata)
                .backmatter(&out_xdata);
        }
        out_xdata.free<cusz::LOC::HOST_DEVICE>();
    }
}

void special_path_spline3(cuszCTX* ctx)
{
    //
}

int main(int argc, char** argv)
{
    auto ctx = new cuszCTX(argc, argv);

    if (ctx->verbose) {
        GetMachineProperties();
        GetDeviceProperty();
    }

    if (ctx->str_predictor == "lorenzo") normal_path_lorenzo(ctx);
    if (ctx->str_predictor == "spline3") special_path_spline3(ctx);
}
