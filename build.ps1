# If you have a proxy, you may need to set the proxy like this:
# $ENV:HTTP_PROXY="http://proxy_host:proxy_port"
# $ENV:HTTPS_PROXY="http://proxy_host:proxy_port"
# you may need to clear the vcpkg cache by remove the folder "$ENV:LOCALAPPDATA\vcpkg\archives"
$ENV:_CL_HACK_CRT=1
$ENV:VCPKG_KEEP_ENV_VARS="_CL_HACK_CRT"

Set-Location $PSScriptRoot
Set-Variable PYMESH_PATH "$(Get-Location)\PyMesh"
Set-Variable VCPKG_PATH "$(Get-Location)\vcpkg"
Set-Variable PATCH_PATH "$(Get-Location)\patches"
$ENV:PYMESH_PATH=$PYMESH_PATH
$ENV:VSLANG=1033

function find_patches {
    Push-Location $PATCH_PATH
    $patches = Get-ChildItem -Path . -Filter "*.patch" -Recurse
    $relativePaths = @()
    $currentDir = Get-Location
    foreach ($file in $patches) {
        $relativePath = $file.FullName.Substring($currentDir.Path.Length + 1)
        $pos = $relativePath.LastIndexOf("\")
        if ($pos -gt 0) {
            $folder = $relativePath.Substring(0, $pos)
            $name = $relativePath.Substring($pos + 1)
        } else {
            $folder = "."
            $name = $relativePath
        }
        $relativePaths += [PSCustomObject]@{
            Folder = $folder
            Name = $name
        }
    }
    Pop-Location
    return $relativePaths
}
function NormalizeEnv {
    param([String] $KeyName)
    $pathComponents = [System.Environment]::GetEnvironmentVariable($KeyName) -split ';'
    $uniquePaths = @()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new()

    # Normalize each path component
    foreach ($component in $pathComponents) {
        # Trim any whitespace and skip empty components
        $component = $component.Trim()
        if (-not [string]::IsNullOrEmpty($component)) {
            try {
                $normalizedPath = [System.IO.Path]::GetFullPath($component).TrimEnd('\')
                if ($seenPaths.Add($normalizedPath)) {
                    $uniquePaths += $normalizedPath
                }
            } catch {
            }
        }
    }
    $newPath = [string]::Join(';', $uniquePaths)
    [System.Environment]::SetEnvironmentVariable($KeyName, $newPath)
    # Write-Host "Normalized: $newPath"
}

if (-Not (Test-Path -Path PyMesh)) {
    git clone --depth 1 --recursive https://github.com/PyMesh/PyMesh.git
    mkdir -ErrorAction Ignore "$PYMESH_PATH\build"
}

# apply patch
if (-Not (Test-Path -Path "$PYMESH_PATH\build\.patch_done_tag")) {
    $patches = find_patches
    foreach ($patch in $patches) {
        $folder = $patch.Folder
        $name = $patch.Name
        Set-Location "$PYMESH_PATH\..\$folder"
        git apply "$PATCH_PATH\$folder\$name"
    }
    New-Item -ItemType File -Path "$PYMESH_PATH/build/.patch_done_tag" -Force
    Set-Location $PSScriptRoot
}

if (-Not (Test-Path -Path "vcpkg\vcpkg.exe")) {
    git clone --depth 1 https://github.com/microsoft/vcpkg.git
    Push-Location vcpkg
    .\bootstrap-vcpkg.bat
    Pop-Location
}


if (Test-Path -Path "$VCPKG_PATH\installed\x64-windows-static\include\gmp.h") {
    $ENV:GMP_INC="$VCPKG_PATH\installed\x64-windows-static\include"
    $ENV:GMP_LIB="$VCPKG_PATH\installed\x64-windows-static\lib"
    $ENV:GMP_INC_DIR="$ENV:GMP_INC"
    $ENV:GMP_LIB_DIR="$ENV:GMP_LIB"
    # Write-Output $ENV:GMP_INC $ENV:GMP_LIB
} else {
    &"$VCPKG_PATH\vcpkg.exe" install gmp:x64-windows-static
}

if (Test-Path -Path "$VCPKG_PATH\installed\x64-windows-static\include\mpfr.h") {
    $ENV:MPFR_INC="$VCPKG_PATH\installed\x64-windows-static\include"
    $ENV:MPFR_LIB="$VCPKG_PATH\installed\x64-windows-static\lib"
    $ENV:MPFR_INC_DIR="$ENV:MPFR_INC"
    $ENV:MPFR_LIB_DIR="$ENV:MPFR_LIB"
} else {
    &"$VCPKG_PATH\vcpkg.exe" install mpfr:x64-windows-static
}

# need boost.
if (-Not (Test-Path -Path "$VCPKG_PATH\installed\x64-windows-static\include\boost")) {
    &"$VCPKG_PATH\vcpkg.exe" install boost:x64-windows-static
}

# don't use tool chain file, we'd like to use only static libraries.
# $ENV:CMAKE_TOOLCHAIN_FILE="$VCPKG_PATH\scripts\buildsystems\vcpkg.cmake"
$ENV:CMAKE_PREFIX_PATH="$VCPKG_PATH\installed\x64-windows-static"

# $ENV:EIGEN_PATH=
if (-Not (Test-Path -Path "$PYMESH_PATH/third_party/build/.all_done_tag")) {
    Set-Location $PYMESH_PATH/third_party
    python build.py all
    if ($?) {
        New-Item -ItemType File -Path "$PYMESH_PATH/third_party/build/.all_done_tag" -Force
    } else {
        exit 1
    }
}

if (-Not (Test-Path -Path "$PYMESH_PATH/build/PyMesh.sln")) {
    Set-Location "$PYMESH_PATH\build"
    cmake ..
}

# build the release version
Set-Location "$PYMESH_PATH\build"
cmake --build . --config Release
if ($?) {
    Set-Location "$PYMESH_PATH\build\tests"
    $ENV:PATH="$PYMESH_PATH\python\pymesh\lib\Release;$PYMESH_PATH\python\pymesh\third_party\bin;$ENV:PATH"
    NormalizeEnv "PATH"
    cmake --build . --config Release --target tests
    
    # build the All-in-one python package
    Set-Location "$PYMESH_PATH"
    $LIBS_PATH=(Resolve-Path ((python -c "import sysconfig; print(sysconfig.get_path('include'))") + "\..\libs")).path
    link /nologo /dll /debug /LTCG /out:PyMesh.cp310-win_amd64.pyd /LIBPATH:$LIBS_PATH /LIBPATH:"$VCPKG_PATH\installed\x64-windows-static\lib" "@..\objs.txt" /nodefaultlib:tbb.lib gmp.lib mpfr.lib    

    Set-Location $PSScriptRoot
} else {
    exit 1
}
