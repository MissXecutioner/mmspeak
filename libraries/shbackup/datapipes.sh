[[ -z "${build_helper_file}" ]] && {
	echo "Missing build helper file. Please define \"build_helper_file\""
	exit 1
}

source ${build_helper_file}
[[ $build_helpers_defined -ne 1 ]] && {
    echo "Failed to include build helpers."
    exit 1
}

# library_path kontrolü
if [[ -z "${library_path}" ]]; then
    echo "ERROR: library_path is not defined!"
    exit 1
fi

requires_rebuild ${library_path}
[[ $? -eq 0 ]] && exit 0

[[ -z "${datapipes_webrtc}" ]] && datapipes_webrtc=1
[[ "${datapipes_webrtc}" -eq 1 ]] && _datapipes_webrtc="ON" || _datapipes_webrtc="OFF"

web_cmake_flags="-DBUILD_WEBRTC=${_datapipes_webrtc}"
if [[ ${build_os_type} != "win32" && "${_datapipes_webrtc}" == "ON" ]]; then

    # GLib dizinini bul
    glib20_dir="$(pwd)/glibc/linux_${build_os_arch}/"
    
    # realpath yerine readlink -f kullan (Ubuntu uyumlu)
    if command -v readlink >/dev/null 2>&1; then
        glib20_dir=$(readlink -f "$glib20_dir" 2>/dev/null || echo "$glib20_dir")
    elif command -v realpath >/dev/null 2>&1; then
        glib20_dir=$(realpath "$glib20_dir" 2>/dev/null || echo "$glib20_dir")
    fi
    
    # lib dizinini bul
    glib20_lib_path=""
    if [[ -d "$glib20_dir/lib" ]]; then
        # lib/ altındaki ilk dizini bul
        for subdir in "$glib20_dir/lib"/*/; do
            if [[ -d "$subdir" ]]; then
                glib20_lib_path="$subdir"
                break
            fi
        done
        
        if [[ -z "$glib20_lib_path" ]]; then
            glib20_lib_path="$glib20_dir/lib"
        fi
    else
        glib20_lib_path="$glib20_dir/lib"
    fi
    
    # Include dizinlerini kontrol et
    includes="$glib20_dir/include;$glib20_dir/include/glib-2.0/"
    if [[ -d "$glib20_lib_path/glib-2.0/include" ]]; then
        includes="$includes;$glib20_lib_path/glib-2.0/include/"
    fi
    
    # Kütüphaneleri kontrol et
    libs=""
    if [[ -f "$glib20_lib_path/libgio-2.0.so" ]]; then
        libs="$glib20_lib_path/libgio-2.0.so"
    else
        libs="z"
    fi
    libs="$libs;resolv"
    [[ -f "$glib20_lib_path/libgmodule-2.0.so" ]] && libs="$libs;$glib20_lib_path/libgmodule-2.0.so"
    [[ -f "$glib20_lib_path/libgobject-2.0.so" ]] && libs="$libs;$glib20_lib_path/libgobject-2.0.so"
    [[ -f "$glib20_lib_path/libffi.so" ]] && libs="$libs;$glib20_lib_path/libffi.so"
    [[ -f "$glib20_lib_path/libglib-2.0.so" ]] && libs="$libs;$glib20_lib_path/libglib-2.0.so"
    libs="$libs;pcre"
    
    # Baştaki noktalı virgülü kaldır (eğer libs boşsa)
    [[ -n "$libs" ]] && libs="${libs#;}"
    
    web_cmake_flags="$web_cmake_flags -DGLIB_PREBUILD_INCLUDES=\"$includes\""
    web_cmake_flags="$web_cmake_flags -DGLIB_PREBUILD_LIBRARIES=\"$libs\""
    
    # libnice dizini
    libnice_dir="../libnice/linux_${build_os_arch}"
    if [[ -e "$libnice_dir" ]]; then
        if command -v readlink >/dev/null 2>&1; then
            libnice_realpath=$(readlink -f "$libnice_dir" 2>/dev/null || echo "$libnice_dir")
        elif command -v realpath >/dev/null 2>&1; then
            libnice_realpath=$(realpath "$libnice_dir" 2>/dev/null || echo "$libnice_dir")
        else
            libnice_realpath="$libnice_dir"
        fi
        web_cmake_flags="$web_cmake_flags -DLIBNICE_PREBUILD_PATH=\"$libnice_realpath\""
    fi
    
    echo "WebRTC flags: $web_cmake_flags"
fi

_cxx_options=""
[[ ${build_os_type} != "win32" ]] && _cxx_options="-fPIC -static-libgcc -static-libstdc++"
[[ ${build_os_type} == "win32" ]] && _cxx_options="-DWIN32"

# Hata veren C++ problemleri için ek flag'ler
# Ubuntu'da GCC için C++17 standardını ve gerekli flag'leri ekle
_extra_cxx_flags=""
if [[ ${build_os_type} != "win32" ]]; then
    _extra_cxx_flags=" -std=c++17 -D_GLIBCXX_USE_CXX11_ABI=1"
    
    # Eksik başlıklar için tanımlamalar
    _extra_cxx_flags="$_extra_cxx_flags -DINCLUDE_STD_STRING -DINCLUDE_STD_STDEXCEPT"
fi

_cxx_options="$_cxx_options$_extra_cxx_flags"

# CMAKE_BUILD_TYPE kontrolü
if [[ -z "${CMAKE_BUILD_TYPE}" ]]; then
    CMAKE_BUILD_TYPE="Release"
fi

general_options="-DCMAKE_C_FLAGS=\"-fPIC\" -DCMAKE_CXX_FLAGS=\"$_cxx_options\" -DBUILD_EXAMPLES=OFF -DBUILD_STATIC=1 -DBUILD_SHARED=1 -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"

# C++ derleyici ve linker flag'leri için ek seçenekler
if [[ ${build_os_type} != "win32" ]]; then
    # Ubuntu/GCC için ek flag'ler
    general_options="$general_options -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_STANDARD_REQUIRED=ON"
    
    # String ve stdexcept için zorunlu include'lar
    general_options="$general_options -DCMAKE_CXX_FLAGS=\"\${CMAKE_CXX_FLAGS} -include string -include stdexcept\""
fi

# OpenSSL dizini
openssl_dir="$(pwd)/openssl-prebuild/${build_os_type}_${build_os_arch}/"
if [[ -e "$openssl_dir" ]]; then
    if command -v readlink >/dev/null 2>&1; then
        openssl_realpath=$(readlink -f "$openssl_dir" 2>/dev/null || echo "$openssl_dir")
    elif command -v realpath >/dev/null 2>&1; then
        openssl_realpath=$(realpath "$openssl_dir" 2>/dev/null || echo "$openssl_dir")
    else
        openssl_realpath="$openssl_dir"
    fi
    crypto_options="-DCRYPTO_TYPE=\"openssl\" -DCrypto_ROOT_DIR=\"$openssl_realpath\""
else
    # Sistem OpenSSL'ini kullan
    crypto_options="-DCRYPTO_TYPE=\"openssl\""
fi

# DataPipes'e özel CMake flag'leri
# String ve exception handling için gerekli tanımlamalar
datapipes_specific_flags=""
if [[ ${build_os_type} != "win32" ]]; then
    datapipes_specific_flags="-DDISABLE_EXCEPTIONS=OFF -DUSE_STD_STRING=ON"
fi

command="cmake_build ${library_path} ${general_options} ${crypto_options} ${web_cmake_flags} ${datapipes_specific_flags} ${CMAKE_OPTIONS}"
eval "$command"
check_err_exit ${library_path} "Failed to build DataPipes!"
set_build_successful ${library_path}
