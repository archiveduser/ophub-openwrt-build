#!/bin/bash
#================================================================================================
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the OpenWrt Image Builder workflow
# https://github.com/ophub/amlogic-s9xxx-openwrt
#
# Description: Build OpenWrt firmware using the official Image Builder
# Copyright (C) 2021~ https://github.com/unifreq/openwrt_packit
# Copyright (C) 2021~ https://github.com/ophub/amlogic-s9xxx-openwrt
# Copyright (C) 2021~ https://downloads.openwrt.org/releases
# Copyright (C) 2023~ https://downloads.immortalwrt.org/releases
#
# Download from: https://downloads.openwrt.org/releases
#                https://downloads.immortalwrt.org/releases
#
# Documentation: https://openwrt.org/docs/guide-user/additional-software/imagebuilder
# Instructions:  Download the official OpenWrt Image Builder,
#                then use it to add packages, libraries, themes, apps, and i18n support.
#
# Command: ./config/imagebuilder/imagebuilder.sh <source:branch>
#          ./config/imagebuilder/imagebuilder.sh openwrt:24.10.4
#
#======================================== Functions list ========================================
#
# error_msg               : Output error message and abort
# download_imagebuilder   : Download and extract the OpenWrt Image Builder
# adjust_settings         : Adjust Image Builder .config settings
# custom_packages         : Download and add custom packages
# custom_config           : Load custom package configuration
# custom_files            : Add custom overlay files
# rebuild_firmware        : Build firmware using Image Builder
# custom_settings         : Apply post-build customizations
#
#================================ Set make environment variables ================================
#
# Set default parameters
make_path="${PWD}"
openwrt_dir="imagebuilder"
imagebuilder_path="${make_path}/${openwrt_dir}"
custom_files_path="${make_path}/config/imagebuilder/files"
custom_config_file="${make_path}/config/imagebuilder/config"
output_path="${make_path}/output"
tmp_path="${imagebuilder_path}/tmp"
unpack_path="${tmp_path}/unpacked_rootfs"

# Set default parameters
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
#
#================================================================================================

# Output error message and abort script execution
error_msg() {
    echo -e "${ERROR} ${1}"
    exit 1
}

# Downloading OpenWrt ImageBuilder
download_imagebuilder() {
    cd ${make_path}
    echo -e "${STEPS} Downloading OpenWrt ImageBuilder..."

    # Downloading imagebuilder files
    if [[ "${op_sourse}" == "immortalwrt" ]]; then
        download_url="immortalwrt.kyarucloud.moe"
    else
        download_url="downloads.openwrt.org"
    fi
    download_file="https://${download_url}/releases/${op_branch}/targets/armsr/armv8/${op_sourse}-imagebuilder-${op_branch}-armsr-armv8.Linux-x86_64.tar.zst"
    curl -fsSOL ${download_file}
    [[ "${?}" -eq "0" ]] || error_msg "Failed to download: [ ${download_file} ]"

    # Unzip and change the directory name
    tar -I zstd -xvf *-imagebuilder-*.tar.zst -C . && sync && rm -f *-imagebuilder-*.tar.zst
    mv -f *-imagebuilder-* ${openwrt_dir}

    sync && sleep 3
    echo -e "${INFO} [ ${make_path} ] directory contents: \n$(ls -lh . 2>/dev/null)"
}

# Adjust related files in the ImageBuilder directory
adjust_settings() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Adjusting ImageBuilder .config settings..."

    # For .config file
    if [[ -s ".config" ]]; then
        # Root filesystem archives
        sed -i "s|CONFIG_TARGET_ROOTFS_CPIOGZ=.*|# CONFIG_TARGET_ROOTFS_CPIOGZ is not set|g" .config
        # Root filesystem images
        sed -i "s|CONFIG_TARGET_ROOTFS_EXT4FS=.*|# CONFIG_TARGET_ROOTFS_EXT4FS is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_SQUASHFS=.*|# CONFIG_TARGET_ROOTFS_SQUASHFS is not set|g" .config
        sed -i "s|CONFIG_TARGET_IMAGES_GZIP=.*|# CONFIG_TARGET_IMAGES_GZIP is not set|g" .config
    else
        echo -e "${INFO} [ ${imagebuilder_path} ] directory contents: \n$(ls -lh . 2>/dev/null)"
        error_msg "No .config file found in [ ${download_file} ]."
    fi

    # For other files
    # ......

    sync && sleep 3
    echo -e "${INFO} [ ${imagebuilder_path} ] directory contents: \n$(ls -lh . 2>/dev/null)"
}

# Add custom packages
# If there is a custom package or ipk you would prefer to use create a [ packages ] directory,
# If one does not exist and place your custom ipk within this directory.
custom_packages() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Adding custom packages..."

    # Create a [ packages ] directory
    [[ -d "packages" ]] || mkdir packages
    cd packages

    # Download luci-app-amlogic
    amlogic_api="https://api.github.com/repos/ophub/luci-app-amlogic/releases"
    # Get the latest release version
    amlogic_plugin_latest_version="$(curl -s ${amlogic_api} | grep tag_name | head -n1 | cut -d '"' -f4)"
    # Get the download URLs for the latest release assets (ipk or apk files)
    amlogic_plugin_list=($(curl -s ${amlogic_api} | grep "browser_download_url" | grep -oE "https.*/${amlogic_plugin_latest_version}/.*\.(ipk|apk)"))

    # Download the latest release assets
    for plugin_url in "${amlogic_plugin_list[@]}"; do
        curl -fsSOJL "${plugin_url}"
        [[ "${?}" -eq "0" ]] && echo -e "${INFO} The [ ${plugin_url} ] is downloaded successfully."
    done

    # Download other luci-app-xxx
    # ......

    # Remove the packages that are not needed based on the Image Builder type (APK or OPKG)
    if grep -q "CONFIG_USE_APK=y" ../.config; then
        echo -e "${INFO} APK-based ImageBuilder detected. Removing .ipk files..."
        rm -f *.ipk

        # Fix the filename format of APK files to be compatible with Image Builder requirements.
        # Image Builder requires that the commit hash in the filename is preceded by a tilde (~) instead of a dot (.).
        for file in *.apk; do
            # Use sed to replace the last dot before the 7-character commit hash with a tilde
            new_file=$(echo "${file}" | sed -E 's/\.([a-f0-9]{7}\.apk)/~\1/')
            if [[ "${file}" != "${new_file}" ]]; then
                mv -f "${file}" "${new_file}" || true
                echo -e "${INFO} Renamed: ${file} -> ${new_file}"
            fi
        done
    else
        echo -e "${INFO} OPKG-based ImageBuilder detected. Removing .apk files..."
        rm -f *.apk
    fi

    sync && sleep 3
    echo -e "${INFO} [ packages ] directory contents: \n$(ls -lh . 2>/dev/null)"
}

# Add custom packages, lib, theme, app and i18n, etc.
custom_config() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Loading custom package configuration..."

    config_list=""
    if [[ -s "${custom_config_file}" ]]; then
        config_list="$(sed -n 's/^CONFIG_PACKAGE_\(.*\)=y$/\1/p' "${custom_config_file}" | tr '\n' ' ')"
        echo -e "${INFO} Custom package list: \n$(echo "${config_list}" | tr ' ' '\n')"
    else
        echo -e "${INFO} No custom configuration file found, skipped."
    fi
}

# Add custom files
# The FILES variable allows custom configuration files to be included in images built with Image Builder.
# The [ files ] directory should be placed in the Image Builder root directory where you issue the make command.
custom_files() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Adding custom files..."

    if [[ -d "${custom_files_path}" ]]; then
        # Copy custom files
        [[ -d "files" ]] || mkdir -p files
        cp -rf ${custom_files_path}/* files

        sync && sleep 3
        echo -e "${INFO} [ files ] directory contents: \n$(ls -lh files/ 2>/dev/null)"
    else
        echo -e "${INFO} No custom files added, skipped."
    fi
}

# Rebuild OpenWrt firmware
rebuild_firmware() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Building OpenWrt firmware with Image Builder..."

    # Selecting default packages, lib, theme, app and i18n, etc.
    my_packages="\
        acpid attr base-files bash bc blkid block-mount blockd bsdtar btrfs-progs busybox bzip2 \
        cgi-io chattr containerd coremark coreutils coreutils-base64 coreutils-nohup \
        coreutils-truncate curl docker docker-compose dockerd dosfstools dumpe2fs e2freefrag e2fsprogs \
        exfat-mkfs f2fs-tools f2fsck fdisk gawk getopt git gzip  iconv jq \
        jshn  libjson-script liblucihttp \
        liblucihttp-lua losetup lsattr lsblk lscpu mkf2fs mount-utils openssl-util parted \
        perl-http-date perlbase-file perlbase-getopt perlbase-time perlbase-unicode perlbase-utf8 \
        pigz ppp ppp-mod-pppoe pv rename resize2fs runc tar tini ttyd tune2fs \
        uclient-fetch nginx-ssl luci-ssl-nginx unzip usb-modeswitch uuidgen wget-ssl whereis \
        which wwan xfs-fsck xfs-mkfs xz xz-utils ziptool zoneinfo-asia zoneinfo-core zstd \
        \
        luci luci-base luci-compat luci-i18n-base-zh-cn luci-lib-base luci-lib-docker \
        luci-lib-ip luci-lib-ipkg luci-lib-jsonc luci-lib-nixio luci-mod-admin-full luci-mod-network \
        luci-mod-status luci-mod-system luci-proto-3g luci-proto-ipip luci-proto-ipv6 \
        luci-app-upnp luci-app-ddns luci-app-wol luci-app-diskman luci-app-nlbwmon luci-app-samba4 luci-app-hd-idle  luci-app-watchcat luci-app-dockerman luci-app-sqm luci-app-msd_lite luci-app-openclash \
        kmod-usb-net-rndis kmod-hwmon-gpiofan adguardhome ddns-scripts-cloudflare openssh-sftp-server luci-proto-wireguard kmod-tcp-bbr kmod-bonding kmod-vrf  \
        luci-app-amlogic shadow-useradd \
        tcpdump nmap iperf3 ethtool hping3 openvpn-openssl sudo screen tree lsof diffutils redis-server mariadb-server mariadb-client \
        luci-i18n-samba4-zh-cn  \
        luci-i18n-diskman-zh-cn luci-i18n-hd-idle-zh-cn openvpn-openssl \
        luci-i18n-sqm-zh-cn luci-i18n-watchcat-zh-cn luci-i18n-nlbwmon-zh-cn \
        luci-i18n-msd_lite-zh-cn rsync openssh-client \
        vim-full bind-dig ntfs-3g ntfs3-mount bluez-utils bluez-daemon \
        ${config_list} \
        "

    # Rebuild firmware
    make image PROFILE="" PACKAGES="${my_packages}" FILES="files"

    sync && sleep 3
    echo -e "${INFO} [ ${openwrt_dir}/bin/targets/*/*/ ] directory contents: \n$(ls -lh bin/targets/*/*/ 2>/dev/null)"
    echo -e "${INFO} Firmware build completed successfully."
}

# Collect packages and generate opkg repository index
collect_packages() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Collecting packages for opkg repository..."

    local packages_dir="${tmp_path}/packages"
    mkdir -p "${packages_dir}"

    # First, try to find .ipk/.apk files in the entire imagebuilder directory
    echo -e "${INFO} Searching for package files in imagebuilder directory..."
    local ipk_count=0
    while IFS= read -r -d '' pkg; do
        local rel_path="${pkg#${imagebuilder_path}/}"
        local rel_dir="$(dirname "${rel_path}")"
        local target_dir="${packages_dir}/${rel_dir}"
        mkdir -p "${target_dir}"
        cp -f "${pkg}" "${target_dir}/"
        ipk_count=$((ipk_count + 1))
    done < <(find "${imagebuilder_path}" -type f \( -name "*.ipk" -o -name "*.apk" \) \
        -not -path "*/tmp/*" -not -path "*/dl/*" -print0 2>/dev/null || true)

    echo -e "${INFO} Found ${ipk_count} package files in imagebuilder directory."

    # If no package files found in build output, extract from the built rootfs
    if [[ ${ipk_count} -eq 0 ]] && [[ -d "${unpack_path}" ]]; then
        echo -e "${INFO} No package files in build output. Extracting package list from rootfs..."

        # Get the list of installed packages from the rootfs opkg status file
        local opkg_status="${unpack_path}/usr/lib/opkg/status"
        local apk_installed="${unpack_path}/lib/apk/db/installed"
        local pkg_list_file="${tmp_path}/installed_packages.list"

        if [[ -f "${opkg_status}" ]]; then
            # OPKG format: extract package names
            grep "^Package:" "${opkg_status}" | awk '{print $2}' > "${pkg_list_file}"
            echo -e "${INFO} Found $(wc -l < "${pkg_list_file}") installed packages (OPKG)."
        elif [[ -f "${apk_installed}" ]]; then
            # APK format: extract package names
            grep "^P:" "${apk_installed}" | awk '{print $2}' > "${pkg_list_file}"
            echo -e "${INFO} Found $(wc -l < "${pkg_list_file}") installed packages (APK)."
        else
            echo -e "${WARNING} No package manager status file found in rootfs."
            return 0
        fi

        # Determine the base repository URL and feed list
        local repo_base=""
        local arch="aarch64_generic"
        local feeds="base luci packages routing telephony"
        if [[ "${op_sourse}" == "immortalwrt" ]]; then
            repo_base="https://downloads.immortalwrt.org/releases/${op_branch}/packages/${arch}"
        else
            repo_base="https://downloads.openwrt.org/releases/${op_branch}/packages/${arch}"
        fi

        # Download Packages index from each feed and build a combined lookup
        local combined_index="${tmp_path}/combined_packages.index"
        : > "${combined_index}"
        for feed in ${feeds}; do
            local feed_url="${repo_base}/${feed}"
            local feed_pkg="${tmp_path}/Packages_${feed}"
            echo -e "${INFO} Downloading package index from ${feed}/..."
            if curl -fsSL "${feed_url}/Packages.gz" -o "${feed_pkg}.gz" 2>/dev/null; then
                gunzip -f "${feed_pkg}.gz" 2>/dev/null || true
                awk -v feed="${feed}" '
                    /^Package:/ { pkg=$2 }
                    /^Filename:/ { print pkg " " feed " " $2 }
                ' "${feed_pkg}" >> "${combined_index}"
                rm -f "${feed_pkg}"
            fi
        done

        local index_count=$(wc -l < "${combined_index}")
        echo -e "${INFO} Combined index has ${index_count} package entries."

        if [[ ${index_count} -eq 0 ]]; then
            echo -e "${WARNING} Failed to download any package indexes."
            return 0
        fi

        # Download each installed package from the correct feed
        local downloaded=0
        local failed=0
        local skipped=0
        while IFS= read -r pkg_name; do
            [[ -z "${pkg_name}" ]] && continue
            local match=""
            match=$(grep "^${pkg_name} " "${combined_index}" | head -n1)
            if [[ -z "${match}" ]]; then
                skipped=$((skipped + 1))
                continue
            fi

            local feed_name=$(echo "${match}" | awk '{print $2}')
            local pkg_filename=$(echo "${match}" | awk '{print $3}')
            local feed_dir="${packages_dir}/${feed_name}"
            mkdir -p "${feed_dir}"

            local dl_url="${repo_base}/${feed_name}/${pkg_filename}"
            local save_name="${pkg_filename##*/}"
            if curl -fsSL "${dl_url}" -o "${feed_dir}/${save_name}" 2>/dev/null; then
                downloaded=$((downloaded + 1))
            else
                failed=$((failed + 1))
                rm -f "${feed_dir}/${save_name}"
            fi
        done < "${pkg_list_file}"

        echo -e "${INFO} Downloaded: ${downloaded}, Failed: ${failed}, Skipped (not in repo): ${skipped}"

        # Generate Packages index for each feed directory
        for feed in ${feeds}; do
            local feed_dir="${packages_dir}/${feed}"
            [[ -d "${feed_dir}" ]] || continue
            local has_ipk=false
            for pkg in "${feed_dir}"/*.ipk; do
                [[ -f "${pkg}" ]] && has_ipk=true && break
            done
            [[ "${has_ipk}" == "true" ]] || continue

            echo -e "${INFO} Generating package index for ${feed}/..."
            (cd "${feed_dir}" && {
                for pkg in *.ipk; do
                    [[ -f "${pkg}" ]] || continue
                    tmp_control=$(mktemp -d)
                    tar -xzf "${pkg}" -C "${tmp_control}" ./control.tar.gz 2>/dev/null || \
                    tar -xzf "${pkg}" -C "${tmp_control}" ./control.tar.xz 2>/dev/null || \
                    tar -xzf "${pkg}" -C "${tmp_control}" ./control.tar.zst 2>/dev/null || true
                    if [[ -f "${tmp_control}/control.tar.gz" ]]; then
                        tar -xzf "${tmp_control}/control.tar.gz" -C "${tmp_control}" ./control 2>/dev/null || true
                    elif [[ -f "${tmp_control}/control.tar.xz" ]]; then
                        tar -xJf "${tmp_control}/control.tar.xz" -C "${tmp_control}" ./control 2>/dev/null || true
                    elif [[ -f "${tmp_control}/control.tar.zst" ]]; then
                        tar -I zstd -xf "${tmp_control}/control.tar.zst" -C "${tmp_control}" ./control 2>/dev/null || true
                    fi
                    if [[ -f "${tmp_control}/control" ]]; then
                        echo "Filename: ${pkg}"
                        cat "${tmp_control}/control"
                        echo ""
                    fi
                    rm -rf "${tmp_control}"
                done
            } > Packages 2>/dev/null)
            gzip -9 -f "${feed_dir}/Packages"
        done

        # Clean up temporary files
        rm -f "${combined_index}" "${pkg_list_file}" "${tmp_path}"/Packages_*
    elif [[ ${ipk_count} -gt 0 ]]; then
        # Generate opkg package index for collected files
        if grep -q "CONFIG_USE_APK=y" .config 2>/dev/null; then
            echo -e "${INFO} APK-based build detected, skipping opkg index generation."
        else
            echo -e "${INFO} Generating opkg package indexes..."
            while IFS= read -r subdir; do
                [[ -d "${subdir}" ]] || continue
                local has_ipk=false
                for pkg in "${subdir}"/*.ipk; do
                    [[ -f "${pkg}" ]] && has_ipk=true && break
                done
                [[ "${has_ipk}" == "true" ]] || continue

                (cd "${subdir}" && {
                    for pkg in *.ipk; do
                        [[ -f "${pkg}" ]] || continue
                        tmp_control=$(mktemp -d)
                        tar -xzf "${pkg}" -C "${tmp_control}" ./control.tar.gz 2>/dev/null || \
                        tar -xzf "${pkg}" -C "${tmp_control}" ./control.tar.xz 2>/dev/null || \
                        tar -xzf "${pkg}" -C "${tmp_control}" ./control.tar.zst 2>/dev/null || true
                        if [[ -f "${tmp_control}/control.tar.gz" ]]; then
                            tar -xzf "${tmp_control}/control.tar.gz" -C "${tmp_control}" ./control 2>/dev/null || true
                        elif [[ -f "${tmp_control}/control.tar.xz" ]]; then
                            tar -xJf "${tmp_control}/control.tar.xz" -C "${tmp_control}" ./control 2>/dev/null || true
                        elif [[ -f "${tmp_control}/control.tar.zst" ]]; then
                            tar -I zstd -xf "${tmp_control}/control.tar.zst" -C "${tmp_control}" ./control 2>/dev/null || true
                        fi
                        if [[ -f "${tmp_control}/control" ]]; then
                            echo "Filename: ${pkg}"
                            cat "${tmp_control}/control"
                            echo ""
                        fi
                        rm -rf "${tmp_control}"
                    done
                } > Packages 2>/dev/null)
                if [[ -f "${subdir}/Packages" ]]; then
                    gzip -9 -f "${subdir}/Packages"
                    echo -e "${INFO} Generated Packages.gz in ${subdir#${packages_dir}/}"
                fi
            done < <(find "${packages_dir}" -type d -print0 2>/dev/null)
        fi
    fi

    # Create the packages archive
    local pkg_file_count=$(find "${packages_dir}" -type f \( -name "*.ipk" -o -name "*.apk" \) 2>/dev/null | wc -l)
    if [[ ${pkg_file_count} -gt 0 ]]; then
        local packages_archive="${output_path}/openwrt-packages-${op_sourse}-${op_branch}.tar.gz"
        echo -e "${INFO} Archiving ${pkg_file_count} packages to ${packages_archive}..."
        (cd "${tmp_path}" && tar -czpf "${packages_archive}" packages/)
        if [[ -f "${packages_archive}" ]]; then
            echo -e "${SUCCESS} Packages archive created: $(ls -lh "${packages_archive}" 2>/dev/null)"
        else
            echo -e "${ERROR} Failed to create packages archive."
        fi
    else
        echo -e "${WARNING} No packages to archive. Skipping."
    fi
}

# Custom settings after rebuild
custom_settings() {
    cd ${imagebuilder_path}
    echo -e "${STEPS} Applying post-build customizations..."

    # Clean up temporary and output directories
    [[ -d "${tmp_path}" ]] && rm -rf "${tmp_path:?}"/* || mkdir -p "${tmp_path}"
    [[ -d "${output_path}" ]] && rm -rf "${output_path:?}"/* || mkdir -p "${output_path}"

    # Find the original *rootfs.tar.gz file
    original_archive="$(ls -1 bin/targets/*/*/*rootfs.tar.gz 2>/dev/null | head -n 1)"

    # Check if the original archive exists
    if [[ ! -f "${original_archive}" ]]; then
        error_msg "No rootfs.tar.gz archive found in build output."
    else
        echo -e "${INFO} Found rootfs archive: ${original_archive}"

        # Get the filename and path
        original_filename="$(basename "${original_archive}")"
        original_path="$(dirname "${original_archive}")"

        # Unpack the original archive
        echo -e "${INFO} Unpacking ${original_filename}..."
        mkdir -p "${unpack_path}"
        tar -xzpf "${original_archive}" -C "${unpack_path}"

        # Modify etc/openwrt_release
        release_file="${unpack_path}/etc/openwrt_release"
        if [[ -f "${release_file}" ]]; then
            echo -e "${INFO} Updating etc/openwrt_release..."
            {
                echo "DISTRIB_SOURCEREPO='github.com/${op_sourse}/${op_sourse}'"
                echo "DISTRIB_SOURCECODE='${op_sourse}'"
                echo "DISTRIB_SOURCEBRANCH='${op_branch}'"
            } >>"${release_file}"
        else
            error_msg "${release_file} not found."
        fi

        # Repack the modified root filesystem
        echo -e "${INFO} Repacking into ${original_filename}..."
        (cd "${unpack_path}" && tar -czpf "${tmp_path}/${original_filename}" ./)

        # Move the repacked archive to the output directory
        echo -e "${INFO} Moving modified rootfs to output directory..."
        mv -f "${tmp_path}/${original_filename}" "${output_path}/"
        # Copy the config file to the output directory
        cp -f .config "${output_path}/config" || true
    fi

    sync && sleep 3
    echo -e "${INFO} [ ${output_path} ] directory contents: \n$(ls -lh ${output_path}/ 2>/dev/null)"
    echo -e "${INFO} Post-build customizations applied successfully."

    # Collect packages before cleaning up the imagebuilder directory
    collect_packages

    # Now clean up
    cd ${make_path}
    rm -rf "${imagebuilder_path}"
    echo -e "${INFO} [ ${output_path} ] final directory contents: \n$(ls -lh ${output_path}/ 2>/dev/null)"
}

# Show welcome message
echo -e "${STEPS} Welcome to the OpenWrt Image Builder."
[[ -x "${0}" ]] || error_msg "Please grant execution permission: [ chmod +x ${0} ]"
[[ -z "${1}" ]] && error_msg "Please specify the OpenWrt source and branch, e.g. [ ${0} openwrt:24.10.4 ]"
[[ "${1}" =~ ^[a-z]{3,}:[0-9]+ ]] || error_msg "Invalid parameter format. Expected <source:branch>, e.g. openwrt:24.10.4"
op_sourse="${1%:*}"
op_branch="${1#*:}"
echo -e "${INFO} Working directory: [ ${PWD} ]"
echo -e "${INFO} Source: [ ${op_sourse} ], Branch: [ ${op_branch} ]"
echo -e "${INFO} Server disk usage before build: \n$(df -hT ${make_path}) \n"
#
# Perform related operations
download_imagebuilder
adjust_settings
custom_packages
custom_config
custom_files
rebuild_firmware
custom_settings
#
# Show server end information
echo -e "${SUCCESS} OpenWrt Image Builder completed successfully."
echo -e "${INFO} Server disk usage after build: \n$(df -hT ${make_path}) \n"
