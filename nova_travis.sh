#!/usr/bin/env bash

# Function to show an informational message
msg() {
    echo -e "\e[1;32m$*\e[0m"
}
err() {
    echo -e "\e[1;41m$*\e[0m"
}

# Ensure ccache is configured and enabled
if [[ $CACHE -eq 1 ]]; then
    ccache -M 50G
    export CC="ccache gcc"
    export CXX="ccache g++"
    export USE_CCACHE=1
    export CCACHE_COMPRESS=1
    export CCACHE_COMPRESSLEVEL=5
    export CCACHE_MAXSIZE=50G
fi

# Get home directory
HOME_DIR="$(pwd)"

# Telegram Setup
git clone --depth=1 https://github.com/elynord/Telegram Telegram

TELEGRAM="$HOME_DIR/Telegram/telegram"
chmod +x $HOME_DIR/Telegram/telegram
send_msg() {
    "${TELEGRAM}" -H -D \
        "$(
            for POST in "${@}"; do
                echo "${POST}"
            done
        )"
}

send_file() {
    "${TELEGRAM}" -H \
        -f "$1" \
        "$2"
}

# Building LLVM's
source "$HOME_DIR"/.bashrc && source "$HOME_DIR"/.profile
msg "Building LLVM's ..."
send_msg "<b>Start build Nova-Clang from <code>[ $BRANCH ]</code> branch</b>"
chmod +x build-llvm.py

# Build LLVM with optimizations
./build-llvm.py \
    --defines LLVM_PARALLEL_COMPILE_JOBS="$(nproc)" LLVM_PARALLEL_LINK_JOBS="$(nproc)" CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3 \
    --install-folder "$HOME_DIR/install" \
    --no-update \
    --no-ccache \
    --quiet-cmake \
    --ref "$BRANCH" \
    --shallow-clone \
    --targets AArch64 ARM X86 \
    --vendor-string "Nova"

# Check if the final clang binary exists or not
if ls install/bin/clang-1* 1> /dev/null 2>&1; then
    msg "LLVM's build successful"
else
    err "LLVM's build failed!"
    send_msg "LLVM's build failed!"
    exit 1
fi

# Build binutils
msg "Build binutils ..."
chmod +x build-binutils.py
./build-binutils.py \
    --install-folder "$HOME_DIR/install" \
    --targets arm aarch64 x86_64

# Remove unused products
rm -fr install/include
rm -f install/lib/*.a install/lib/*.la

# Strips remaining products
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
    strip -s "${f::-1}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
    # Remove last character from file output (':')
    bin="${bin::-1}"

    echo "$bin"
    patchelf --set-rpath "$DIR/../lib" "$bin"
done

# Git config
git config --global user.name "ftrsndrya"
git config --global user.email "fitri.81310740@smkpgriwonoasri.sch.id"

# Get Clang Info
pushd "$HOME_DIR"/src/llvm-project || exit
llvm_commit="$(git rev-parse HEAD)"
short_llvm_commit="$(cut -c-8 <<<"$llvm_commit")"
popd || exit
llvm_commit_url="https://github.com/llvm/llvm-project/commit/$short_llvm_commit"
clang_version="$("$HOME_DIR"/install/bin/clang --version | grep "version" | awk '{print $4}')"
build_date="$(TZ=Asia/Jakarta date +"%Y-%m-%d")"
tags="Nova-Clang-$clang_version-release"
file="Nova-Clang-$clang_version.tar.gz"
clang_link="https://github.com/ftrsndrya/Nova-Clang/releases/download/$tags/$file"

# Get binutils version
binutils_version=$(grep "LATEST_BINUTILS_RELEASE" build-binutils.py)
binutils_version=$(echo "$binutils_version" | grep -oP '\(\s*\K\d+,\s*\d+,\s*\d+' | tr -d ' ')
binutils_version=$(echo "$binutils_version" | tr ',' '.')

# Create simple info
pushd "$HOME_DIR"/install || exit
{
    echo "# Quick Info
* Build Date : $build_date
* Clang Version : $clang_version
* Binutils Version : $binutils_version
* Compiled Based : $llvm_commit_url"
} >>README.md
tar -czvf ../"$file" .
popd || exit

# Push
git clone "https://ftrsndrya:$GIT_TOKEN@github.com/ftrsndrya/Nova-Clang" rel_repo
pushd rel_repo || exit
if [ -d "$BRANCH" ]; then
    echo "$clang_link" >"$BRANCH"/link.txt
    cp -r "$HOME_DIR"/install/README.md "$BRANCH"
else
    mkdir -p "$BRANCH"
    echo "$clang_link" >"$BRANCH"/link.txt
    cp -r "$HOME_DIR"/install/README.md "$BRANCH"
fi
git add .
git commit -asm "Nova-Clang-$clang_version: $(TZ=Asia/Jakarta date +"%Y%m%d")"
git push -f origin main

# Check tags already exists or not
overwrite=y
git tag -l | grep "$tags" || overwrite=n
popd || exit

# Upload to github release
failed=n
if [ "$overwrite" == "y" ]; then
    chmod +x github-release
    ./github-release edit \
        --security-token "$GIT_TOKEN" \
        --user "ftrsndrya" \
        --repo "Nova-Clang" \
        --tag "$tags" \
        --description "$(cat "$(pwd)"/install/README.md)"

    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "ftrsndrya" \
        --repo "Nova-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$(pwd)/$file" \
        --replace || failed=y
else
    ./github-release release \
        --security-token "$GIT_TOKEN" \
        --user "ftrsndrya" \
        --repo "Nova-Clang" \
        --tag "$tags" \
        --description "$(cat "$(pwd)"/install/README.md)"

    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "ftrsndrya" \
        --repo "Nova-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$(pwd)/$file" || failed=y
fi

# Handle uploader if upload failed
while [ "$failed" == "y" ]; do
    failed=n
    chmod +x github-release
    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "ftrsndrya" \
        --repo "Nova-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$(pwd)/$file" \
        --replace || failed=y
done

# Send message to telegram
send_msg "
<b>----------------- Quick Info -----------------</b>
<b>Build Date : </b>
* <code>$build_date</code>
<b>Clang Version : </b>
* <code>$clang_version</code>
<b>Binutils Version : </b>
* <code>$binutils_version</code>
<b>Compile Based : </b>
* <a href='$llvm_commit_url'>$llvm_commit_url</a>
<b>Push Repository : </b>
* <a href='https://github.com/ftrsndrya/Nova-Clang.git'>Nova-Clang</a>
<b>-------------------------------------------------</b>"
