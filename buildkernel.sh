#!/bin/bash
export ARCH=arm64
export KBUILD_BUILD_USER=LiuNian
export KBUILD_BUILD_HOST=wloot
export KJOBS="$((`grep -c '^processor' /proc/cpuinfo` * 2))"

#ccache=$(which ccache)

function clone_clang()
{
  CLANG_VERSION="clang-r353983e"
  git clone https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 clang
  cd clang
  find . | grep -v ${CLANG_VERSION} | xargs rm -rf
  CLANG_PATH="${PWD}/${CLANG_VERSION}"
  cd ..
}

function clone_proton_clang()
{
  curl -LfH "Accept: application/octet-stream" "$(curl -sSf "https://api.github.com/repos/kdrag0n/proton-clang-build/releases/latest" | jq -r '.assets[0].url')" | tar -I zstd -xf -
  CLANG_VERSION="CLANG 10"
  mv proton_clang* clang
  echo "deb http://archive.ubuntu.com/ubuntu eoan main" >> /etc/apt/sources.list && apt-get update
  apt-get install libc6 libstdc++6 libgnutls30 -y
  CLANG_PATH="${PWD}/clang"
}

function clone_gcc()
{
  GCC64_TYPE="aarch64-elf-"
  GCC32_TYPE="arm-eabi-"
  GCC_VERSION="GCC 9"
  git clone https://github.com/kdrag0n/${GCC64_TYPE}gcc
  git clone https://github.com/kdrag0n/${GCC32_TYPE}gcc
  GCC64="${ccache} ${PWD}/${GCC64_TYPE}gcc/bin/${GCC64_TYPE}"
  GCC32="${ccache} ${PWD}/${GCC32_TYPE}gcc/bin/${GCC32_TYPE}"
}

function install_ubuntu_gcc()
{
  apt-get install gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi -y
  GCC64_TYPE=aarch64-linux-gnu-
  GCC64=aarch64-linux-gnu-
  GCC32=arm-linux-gnueabi-
}

#输出目录 设备
function build_gcc()
{
  rm -rf ${1}/arch/arm64/boot
  make O=${1} ${2}_defconfig
  make -j${KJOBS} O=${1} CROSS_COMPILE="${GCC64}" CROSS_COMPILE_ARM32="${GCC32}"
  if [ $? -ne 0 ]; then
    errored "为${2}构建时出错， 终止。。。"
  fi
}
function build_clang()
{
  rm -rf ${1}/arch/arm64/boot
  make O=${1} ${2}_defconfig
  make -j${KJOBS} O=${1} CC="${CLANG}" CLANG_TRIPLE=${GCC64_TYPE} CROSS_COMPILE="${GCC64}" CROSS_COMPILE_ARM32="${GCC32}"
  if [ $? -ne 0 ]; then
    errored "为${2}构建时出错， 终止。。。"
  fi
}

#设备名
function work_zip()
{
  git clone https://github.com/wloot/AnyKernel2
  ZIPNAME=LoverOrientedKernel-${1}-${DRONE_BUILD_NUMBER}-MIUI-${GITHEAD}.zip
  cp ${OUT_DIR}/arch/arm64/boot/Image.gz-dtb AnyKernel2
  cd AnyKernel2
  zip -r ${ZIPNAME} *
  telegram_upload ${ZIPNAME}
  rm ${ZIPNAME} Image.gz-dtb
  cd $(dirname "$PWD")
}

#文件路径
function telegram_upload()
{
  curl -s https://api.telegram.org/bot"${BOTTOKEN}"/sendDocument -F document=@"${1}" -F chat_id="${CHATID}"
}

#消息内容
function telegram_notify()
{
  curl -s https://api.telegram.org/bot"${BOTTOKEN}"/sendMessage -d parse_mode="Markdown" -d text="${1}" -d chat_id="${CHATID}"
}
function errored()
{
  telegram_notify "${1}"
  exit 1
}

####################################
#   sagit and chiron build for drone.io   #
####################################

cd ${HOME}
#clone_gcc
install_ubuntu_gcc
if [[ "$@" =~ "clang" ]]; then
  clone_proton_clang
  CLANG="${ccache} ${CLANG_PATH}/bin/clang"
  export PATH=${CLANG_PATH}/bin:$PATH LD_LIBRARY_PATH=${CLANG_PATH}/lib:$LD_LIBRARY_PATH
fi

OUT_DIR=${HOME}/out
START=$(date +"%s")
cd ${HOME}/src
GITHEAD=$(git rev-parse --short HEAD)

if [[ "$@" =~ "clang" ]]; then
  telegram_notify "开始新的构建#${DRONE_BUILD_NUMBER}， 使用${CLANG_VERSION}编译中。。。。"
  build_clang ${OUT_DIR} sagit
else
  telegram_notify "开始新的构建#${DRONE_BUILD_NUMBER}， 使用${GCC_VERSION}编译中。。。。"
  build_gcc ${OUT_DIR} sagit
fi
work_zip sagit

if [[ "$@" =~ "clang" ]]; then
  build_clang ${OUT_DIR} chiron
else
  build_gcc ${OUT_DIR} chiron
fi
work_zip chiron
END=$(date +"%s")
KDURTION=$((END - START))
telegram_notify "实时构建完毕， 耗时 $((KDURTION / 60)) 分 $((KDURTION % 60)) 秒"
