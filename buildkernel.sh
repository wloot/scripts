#!/bin/bash
export KBUILD_BUILD_USER=LiuNian
export KBUILD_BUILD_HOST=wloot
export KJOBS="$((`grep -c '^processor' /proc/cpuinfo` * 2))"

ccache=$(which ccache)

function clone_clang()
{
  CLANG_VERSION="google clang 9.0.6"
#  git clone https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 clang
#  cd clang
#  find . | grep -v ${CLANG_VERSION} | xargs rm -rf
#  CLANG_PATH="${PWD}/${CLANG_VERSION}"
  git clone https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-5799447 clang --depth=1
  CLANG_PATH="${PWD}/clang"
  cd ..
}

function clone_custom_clang()
{
  echo "deb http://archive.ubuntu.com/ubuntu eoan main" >> /etc/apt/sources.list && apt-get update
  apt-get --no-install-recommends install libc6 libstdc++6 libgnutls30 ccache -y
  git clone https://github.com/kdrag0n/proton-clang --depth=1 -b master clang
  CLANG_VERSION="CLANG 10"
  CLANG_PATH="${PWD}/clang"
  GCC64="${CLANG_PATH}/bin/aarch64-linux-gnu-"
  GCC32="${CLANG_PATH}/bin/arm-linux-gnueabi-"
  GCC64_TYPE="aarch64-linux-gnu-"
}

function clone_gcc()
{
  GCC64_TYPE="aarch64-elf-"
  GCC32_TYPE="arm-eabi-"
  GCC_VERSION="GCC 9"
  git clone https://github.com/kdrag0n/${GCC64_TYPE}gcc --depth=1
  git clone https://github.com/kdrag0n/${GCC32_TYPE}gcc --depth=1
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
  make O=${1} ARCH=arm64 ${2}_defconfig
  make -j${KJOBS} O=${1} ARCH=arm64 CROSS_COMPILE="${GCC64}" CROSS_COMPILE_ARM32="${GCC32}"
  if [ $? -ne 0 ]; then
    errored "为${2}构建时出错， 终止。。。"
  fi
}
function build_clang()
{
  rm -rf ${1}/arch/arm64/boot
  make O=${1} ARCH=arm64 ${2}_defconfig
  make -j${KJOBS} O=${1} ARCH=arm64 CC="${ccache} clang" AR="llvm-ar" NM="llvm-nm" OBJCOPY="llvm-objcopy" OBJDUMP="llvm-objdump" STRIP="llvm-strip" CROSS_COMPILE="${GCC64}" CROSS_COMPILE_ARM32="${GCC32}" CLANG_TRIPLE="${GCC64_TYPE}"
  if [ $? -ne 0 ]; then
    errored "为${2}构建时出错， 终止。。。"
  fi
}

#设备名
function work_zip()
{
  git clone https://github.com/wloot/AnyKernel2
  ZIPNAME=LoverOrientedKernel-${TRAVIS_BUILD_NUMBER}-${1}-MIUI-${GITHEAD}.zip
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

function pickcommit()
{
  git add .
  git cherry-pick --no-commit "${1}"
  if [ "$?" != "0" ]; then
    errored "打补丁失败 ${1}"
  fi
}

####################################
#   sagit and chiron build for travis ci   #
####################################

cd ${HOME}
if [[ "$@" =~ "gcc" ]]; then
  clone_gcc
fi
if [[ "$@" =~ "clang" ]]; then
  clone_custom_clang
  export LD_LIBRARY_PATH="${CLANG_PATH}/lib:${CLANG_PATH}/lib64:$LD_LIBRARY_PATH"
  export PATH="${CLANG_PATH}/bin:$PATH"
fi

OUT_DIR=${HOME}/out
START=$(date +"%s")
cd ${TRAVIS_BUILD_DIR}
#git fetch https://$GITID:$GITPWD@github.com/wloot/tmp.git idv3p
#pickcommit efbf36a60e55f8ed551d1b7ad5c10eff1caa7f7c
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
