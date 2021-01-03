#ifndef CUSZ_METADATA_HH
#define CUSZ_METADATA_HH

/**
 * @file metadata.hh
 * @author Jiannan Tian
 * @brief
 * @version 0.1.1
 * @date 2020-09-22
 *
 * @copyright (C) 2020 by Washington State University, Argonne National Laboratory
 * See LICENSE in top-level directory
 *
 */

#include <cstddef>
#include <string>
#include <unordered_map>

struct Metadata {
    int block{};
    int ndim{};
    int len = 1;
    int d0{1}, d1{1}, d2{1}, d3{1};
    int stride0{}, stride1{}, stride2{}, stride3{};
    int nb0{}, nb1{}, nb2{}, nb3{};  // nb3 not usable in dim
    int cap{}, radius{};
    int nnz{};

    double eb{}, ebx2{}, eb_r{}, ebx2_r{};
    // TODO caution! host-device sync
    size_t total_bits{}, total_uint{}, huff_metadata_size{};
};

template <int ndim>
struct MetadataTrait;

// clang-format off
template <> struct MetadataTrait<1>     { static const int Block = 256; };
template <> struct MetadataTrait<0x101> { static const int Block = 128; };
template <> struct MetadataTrait<0x201> { static const int Block = 64;  };
template <> struct MetadataTrait<2>     { static const int Block = 16;  };
template <> struct MetadataTrait<3>     { static const int Block = 8;   };
// clang-format on

void cuszSetDim(struct Metadata*, int, int, int, int, int);

void cuszSetDemoDim(struct Metadata*, std::string const&);

void cuszSetErrorBound(struct Metadata*, double);

void cuszSetQuantBinNum(struct Metadata*, int);

void cuszChangeToR2RModeMode(struct Metadata*, double);

#endif