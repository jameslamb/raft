#!/bin/bash
# Copyright (c) 2023-2024, NVIDIA CORPORATION.

set -euo pipefail

package_name=$1
package_dir=$2
underscore_package_name=$(echo "${package_name}" | tr "-" "_")

# Clear out system ucx files to ensure that we're getting ucx from the wheel.
rm -rf /usr/lib64/ucx
rm -rf /usr/lib64/libuc*

source rapids-configure-sccache
source rapids-date-string

RAPIDS_PY_CUDA_SUFFIX="$(rapids-wheel-ctk-name-gen ${RAPIDS_CUDA_VERSION})"

rapids-logger "Generating build requirements"
matrix_selectors="cuda=${RAPIDS_CUDA_VERSION%.*};arch=$(arch);py=${RAPIDS_PY_VERSION};cuda_suffixed=true"

rapids-dependency-file-generator \
  --output requirements \
  --file-key "py_build_${underscore_package_name}" \
  --matrix "${matrix_selectors}" \
| tee /tmp/requirements-build.txt

rapids-dependency-file-generator \
  --output requirements \
  --file-key "py_rapids_build_${underscore_package_name}" \
  --matrix "${matrix_selectors}" \
| tee -a /tmp/requirements-build.txt

rapids-logger "Installing build requirements"
python -m pip install \
    -v \
    --prefer-binary \
    -r /tmp/requirements-build.txt

rapids-generate-version > ./VERSION

cd "${package_dir}"

case "${RAPIDS_CUDA_VERSION}" in
  12.*)
    EXCLUDE_ARGS=(
      --exclude "libcublas.so.12"
      --exclude "libcublasLt.so.12"
      --exclude "libcurand.so.10"
      --exclude "libcusolver.so.11"
      --exclude "libcusparse.so.12"
      --exclude "libnvJitLink.so.12"
      --exclude "libucp.so.0"
    )
  ;;
  11.*)
    EXCLUDE_ARGS=(
      --exclude "libucp.so.0"
    )
  ;;
esac

rapids-logger "Building '${package_name}' wheel"
python -m pip wheel \
    -w dist \
    -v \
    --no-build-isolation \
    --no-deps \
    --disable-pip-version-check \
    .

sccache --show-adv-stats

mkdir -p final_dist
python -m auditwheel repair -w final_dist "${EXCLUDE_ARGS[@]}" dist/*

RAPIDS_PY_WHEEL_NAME="${underscore_package_name}_${RAPIDS_PY_CUDA_SUFFIX}" rapids-upload-wheels-to-s3 final_dist
