<img src="https://user-images.githubusercontent.com/10354752/81179956-05860600-8f70-11ea-8b01-856f29b9e8b2.jpg" width="150">

cuSZ: A GPU Accelerated Error-Bounded Lossy Compressor for Scientific Data
---

cuSZ is a CUDA implementation of the world-widely used [SZ lossy compressor](https://github.com/szcompressor/SZ). It is the first error-bounded lossy compressor on GPUs for scientific data, which significantly improves SZ's throughput in GPU-based heterogeneous HPC systems. 

(C) 2020 by Washington State University and Argonne National Laboratory. See COPYRIGHT in top-level directory.

* Developers: Jiannan Tian, Cody Rivera, Dingwen Tao, Sheng Di, Franck Cappello
* Contributors: Megan Hickman Fulp, Robert Underwood, Kai Zhao, Xin Liang, Jon Calhoun

# citation
**Kindly note**: If you mention cuSZ in your paper, please cite the following reference which covers the whole design and implementation of the latest version of cuSZ.

* Jiannan Tian, Sheng Di, Kai Zhao, Cody Rivera, Megan Hickman Fulp, Robert Underwood, Sian Jin, Xin Liang, Jon Calhoun, Dingwen Tao, Franck Cappello. "[cuSZ: An Efficient GPU-Based Error-Bounded Lossy Compression Framework for Scientific Data](https://arxiv.org/abs/2007.09625)", in Proceedings of the 29th International Conference on Parallel Architectures and Compilation Techniques (PACT), Atlanta, GA, USA, 2020.

This document simply introduces how to install and use the cuSZ compressor on NVIDIA GPUs. More details can be found in doc/cusz-doc.pdf.

# set up
## requirements
- NVIDIA GPU with Pascal (in progress), Volta, or Turing microarchitectures 
- Minimum: CUDA 9.2+ and GCC 7.3+ (with C++14 support)
  - The below table shows our tested GPUs, CUDA versions, and compilers.
  - Note that CUDA version here refers to the toolchain verion (e.g., activiated CUDA via `module load`), whereas CUDA runtime version (according to SM) can be lower than that.
  - Please refer to [link](https://gist.github.com/ax3l/9489132) for more details about different CUDA versions and their required compilers.
  
| GPU       | microarch | SM  | CUDA version | gcc version |
| --------- | --------- | --- | ------------ | ----------- |
| V100      | Volta     | 70  | 10.2         | 7.3/8.4     |
|           |           |     | 9.2          | 7.3         |
| RTX 5000  | Turing    | 75  | 10.1         | 7.3/8.3     |
| RTX 2060S | Turing    | 75  | 11.0/11.1    | 9.3         |


## download
```bash
git clone git@github.com:szcompressor/cuSZ.git
```

## compile
```bash
cd cuSZ
export CUSZ_ROOT=$(pwd)
make
sudo make install   # optional given that it's a sudo
# otherwise, without `sudo make install`, `./$(CUSZ_ROOT)/bin/cusz` to execute
```

Commands `cusz` or `cusz -h` are for instant instructions.

# use
## basic use

The basic use cuSZ is given below.

```bash
./bin/cusz -f32 -m r2r -e 1.0e-4.0 -i ./data/sample-cesm-CLDHGH -D cesm -z
             |  ------ ----------- ---------------------------- -------  |
           dtype mode  error bound        input datum file        demo   zip

./bin/cusz -i ./data/sample-cesm-CLDHGH -x
           ----------------------------  |
           corresponding datum basename  unzip
```
`-D cesm` specifies preset dataset for demonstration. In this case, it is CESM-ATM, whose dimension is 1800-by-3600, following y-x order. To otherwise specify datum file and input dimensions arbitrarily, we use `-2 3600 1800`, then it becomes

```bash
cusz -f32 -m r2r -e 1e-4 -i ./data/sample-cesm-CLDHGH -2 3600 1800 -z
```
To conduct compression, several input arguments are **necessary**,

- `-z` or `--zip` to compress
- `-x` or `--unzip` to decompress
- `-m` or `--mode` to specify compression mode. Options include `abs` (absolute value) and `r2r` (relative to value range).
- `-e` or `--eb` to specify error bound
- `-i` to specify input datum file
- `-D` to specify demo dataset name or `-{1,2,3}` to input dimensions
- `--opath` to specify output path for both compression and decompresson.




## tuning
There are also internal a) quant. code representation, b) Huffman codeword representation, and c) chunk size for Huffman coding exposed. Each can be specified with argument options.

- `-Q` or `--quant-rep`  to specify bincode/quant. code representation. Options `<8|16|32>` are for `uint8_t`, `uint16_t`, `uint32_t`, respectively. (Manually specifying this may not result in optimal memory footprint.)
- `-H` or `--huffman-rep`  to specify Huffman codeword representation. Options `<32|64>` are for `uint32_t`, `uint64_t`, respectively. (Manually specifying this may not result in optimal memory footprint.)
- `-C` or `--huffman-chunk`  to specify chunk size for Huffman codec. Should be a power-of-2 that is sufficiently large (`[256|512|1024|...]`). (This affects Huffman decoding performance *significantly*.)


## with preprocessing
Some application such as EXAFEL preprocesses with binning [^binning] in addition to skipping Huffman codec.

[^binning]: A current binning setting is to downsample a 2-by-2 cell to 1 point.

## disabling modules
For EXAFEL, given binning and `uint8_t` have already resulted in a compression ratio of up to 16, Huffman codec may not be needed in a real-world use scenario, so Huffman codec can be skipped with `--skip huffman`.

Decompression can give a full preview of the whole workflow and writing data of the orignal size to the filesystem is long, so writing decompressed data to filesystem can be skipped with `--skip write.x`. 

A combination of modules can be `--skip huffman,write.x`.

Other module skipping for use scenarios are in development.

## use as an analytical tool

`--dry-run` or `-r` in place of `-z` and/or `-x` enables dry-run mode to get PSNR. This employs the feature of dual-quantization that the decompressed data is guaranteed the same with prequantized data.

# hands-on examples

1. run a 2D CESM demo at 1e-4 relative to value range

	```bash
	# compress
	cusz -f32 -m r2r -e 1e-4 -i ./data/sample-cesm-CLDHGH -D cesm -z
	# decompress, use the datum to compress as basename
	cusz -i ./data/sample-cesm-CLDHGH -x
	# decompress, and compare with the original data
	cusz -i ./data/sample-cesm-CLDHGH -x --origin ./data/sample-cesm-CLDHGH
	```
2. runa 2D CESM demo with specified output path

	```bash
	mkdir data2 data3
	# output compressed data to `data2`
	cusz -f32 -m r2r -e 1e-4 -i ./data/sample-cesm-CLDHGH -D cesm -z --opath data2
	# output decompressed data to `data3`
	cusz -i ./data2/sample-cesm-CLDHGH -x --opath data3
	```
3. run CESM demo with `uint8_t` and 256 quant. bins

	```bash
	cusz -f32 -m r2r -e 1e-4 -i ./data/sample-cesm-CLDHGH -D cesm -z -x -d 256 -Q 8
	```
4. in addition to the previous command, if skipping Huffman codec,

	```bash
	cusz -f32 -m r2r -e 1e-4 -i ./data/sample-cesm-CLDHGH -D cesm -z -d 256 -Q 8 \
		--skip huffman  # or `-X huffman`
	cusz -i ./data/sample-cesm-CLDHGH -x  # `-d`, `-Q`, `-X` is recorded
	```
5. some application such as EXAFEL preprocesses with binning [^binning] in addition to skipping Huffman codec

	```bash
	cusz -f32 -m r2r -e 1e-4 -i ./data/sample-cesm-CLDHGH -D cesm -z -x \
		-d 256 -Q 8 --pre binning --skip huffman	# or `-p binning`
	```
6. dry-run to get PSNR and to skip real compression or decompression; `-r` also works alternatively to `--dry-run`

	```bash
	# This works equivalently to decompress with `--origin /path/to/origin-datum`
	cusz -f32 -m r2r -e 1e-4 -i ./data/sample-cesm-CLDHGH -D cesm --dry-run	# or `-r`
	```

# tested by team
## tested datasets

We have successfully tested cuSZ on the following datasets from [Scientific Data Reduction Benchmarks](https://sdrbench.github.io/):
| dataset          | dim. | description                                                             |
| ---------------- | ---- | ----------------------------------------------------------------------- |
| EXAALT           | 1D   | molecular dynamics simulation                                           |
| HACC             | 1D   | cosmology: particle simulation                                          |
| CESM-ATM         | 2D   | climate simulation                                                      |
| EXAFEL           | 2D   | images from the LCLS instrument                                         |
| Hurricane ISABEL | 3D   | weather simulation                                                      |
| NYX              | 3D   | cosmology: adaptive mesh hydrodynamics + N-body cosmological simulation |

## sample kernel performance (compression/zip)


|                    |               |               | dual-quant  | hist       | codebook    | encode       | outlier     | OVERALL (w/o c/b) | mem bw (ref)     | memcpy (ref) |
| ------------------ | ------------- | ------------- | ----------- | ---------- | ----------- | ------------ | ----------- | ----------------- | ---------------- | ------------ |
| 2D CESM (25.7 MiB) | **V100**      | *time* (us)      | 103.6  | 45.54  | 820.6 | 448.6  | 140.3 | 738.0           |                  |            |
|                    |               | *throughput* (GB/s)      | 260.1  | 591.8  |        | 60.1    | 192.0  | 36.5             | 900 (HBM2)  | 713.1  |
|                    | **RTX 5000**  | *time* (us)      | 409.7  | 83.9   | 681.5 | 870.2  | 204.4 | 1379.4          |                  |            |
|                    |               | *throughput* (GB/s)      | 65.8   | 321.3  |        | 31.0    | 131.9  | 19.5             | 448 (GDDR6) | 364.5  |
|                    | **RTX 2060S** | *time* (us)      | 535.58 | 112.0  | 601.5 | 1134.6 | 294.1 | 1543.2          |                  |            |
|                    |               | *throughput* (GB/s)      | 50.3   | 240.7  |        | 23.8    | 91.6   | 17.5             | 448 (GDDR6) | 379.6  |
| 3D NYX (512 MiB)   | **V100**      | *time* (ms)      | 2.69   | 1.34   | 0.68  | 8.37   | 2.00  | 14.4            |                  |            |
|                    |               | *throughput* (GB/s)      | 199.6  | 400.6  |        | 64.1    | 268.4  | 37.3             | 900 (HBM2)  | 713.1  |
|                    | **RTX 5000**  | *time* (ms)      | 10.15  | 3.58   | 0.55  | 14.48  | 5.20  | 33.4            |                  |            |
|                    |               | *throughput* (GB/s)      | 52.9   | 150.0  |        | 37.1    | 103.2  | 16.1             | 448 (GDDR6) | 364.5  |
|                    | **RTX 2060S** | *time* (ms)      | 13.53  | 5.58   | 0.47  | 18.13  | 7.01  | 44.25           |                  |            |
|                    |               | *throughput* (GB/s)      | 39.7   | 96.2   |        | 29.6    | 76.6   | 12.1             | 448 (GDDR6) | 379.6  |

## limitations of this version (0.1.1)

- For this release, cuSZ only supports 32-bit `float`-type datasets. We will support 64-bit `double`-type datasets in the future release. 
- The compression ratio of current cuSZ may be different from SZ on CPU. Unlike SZ, cuSZ so far does not include an LZ-based lossless compression as the last step for compression throughput consideration; in other words, the compression ratio is up to 32. We are working on an efficient LZ-based lossless compression to be integrated into cuSZ in the future release.
- For this release, compressed data is saved in five files, including `.canon` file for canonical codebook (for decompression), `.hbyte` file for Huffman bitstream, `.hmeata` file for chucked Huffman bitstream metadata, `.outlier` file for unpredicted data with its metadata (in `CSR` format), and `.yamp` file for metadata pack of compressed data. Moreover, if you use `--skip huffman`, `uint<8|16|32>_t` quantization codes are saved in `.quant` file. We will change the compressed format in the next release. 
- The current integrated Huffman codec runs with efficient histogramming [1], parallel Huffman codebook building [2], memory-copy style encoding, chunkwise bit deflating, and efficient Huffman decoding using canonical codes [3]. However, the chunkwise bit deflating is not optimal, so we are woking on a faster, finer-grained Huffman codec for the future release. 
- We are working on refactoring to support more predictors, preprocessing methods, and compression modes. More functionalities will be released in the next release.
- Please use `-H 64` for HACC dataset because 32-bit representation is not enough for multiple HACC variables. Using `-H 32` will make cuSZ report an error. We are working on automatically adpating 32- or 64-bit representation for different datasets. 
- You may see a performance degradation when handling large-size dataset, such as 1-GB or 4-GB HACC. We are working on autotuning consistent performance.
- Please refer to [_Project Management page_](https://github.com/szcompressor/cuSZ/projects/2) for more TODO details.  

# references

[1] 
Gómez-Luna, Juan, José María González-Linares, José Ignacio Benavides, and Nicolás Guil. "An optimized approach to histogram computation on GPU." Machine Vision and Applications 24, no. 5 (2013): 899-908.

[2]
Ostadzadeh, S. Arash, B. Maryam Elahi, Zeinab Zeinalpour, M. Amir Moulavi, and Koen Bertels. "A Two-phase Practical Parallel Algorithm for Construction of Huffman Codes." In PDPTA, pp. 284-291. 2007.

[3]
Klein, Shmuel T. "Space-and time-efficient decoding with canonical huffman trees." In Annual Symposium on Combinatorial Pattern Matching, pp. 65-75. Springer, Berlin, Heidelberg, 1997.

# acknowledgements
This R&D was supported by the Exascale Computing Project (ECP), Project Number: 17-SC-20-SC, a collaborative effort of two DOE organizations – the Office of Science and the National Nuclear Security Administration, responsible for the planning and preparation of a capable exascale ecosystem. This repository was based upon work supported by the U.S. Department of Energy, Office of Science, under contract DE-AC02-06CH11357, and also supported by the National Science Foundation under Grants [CCF-1617488](https://www.nsf.gov/awardsearch/showAward?AWD_ID=1617488), [CCF-1619253](https://www.nsf.gov/awardsearch/showAward?AWD_ID=1619253), [OAC-2003709](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2003709), [OAC-1948447/2034169](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2034169), and [OAC-2003624/2042084](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2042084).

![acknowledgement](https://user-images.githubusercontent.com/5705572/93790911-6abd5980-fbe8-11ea-9c8d-c259260c6295.jpg)
