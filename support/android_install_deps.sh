#!/bin/bash

set -e

if [[ x"`uname -o`" != x"GNU/Linux" ]] ; then
  printf >&2 'Host OS %s is unsupported! Only GNU/Linux is supported!\n' "`uname -o`"
fi
if [[ x"`uname -p`" != x"x86_64" ]] ; then
  printf >&2 'Host architecture %s is unsupported! Only x86_64 is supported!\n' "`uname -p`"
fi

function updateAutotoolsToolchainDetection() {
  # If a source tarball was bootstrapped with older autotools,
  # it may show an error that the toolchain is broken/unsupported.
  # This function will update config.guess and config.sub
  # to support latest cross-compiler toolchains and architectures.
  # @param $1: path to search for outdated files.
  
  CONFIG_VER="config"
  CONFIG_SOURCEDIR=$DEPS_SOURCE/$CONFIG_VER
  CONFIG_INSTALLDIR=$1
  
  cd $DEPS_SOURCE
  if [ ! -d $CONFIG_SOURCEDIR ]; then
    git clone git://git.sv.gnu.org/config.git
    cd $CONFIG_SOURCEDIR
    git reset --hard 5049811e672
  fi
  cd $CONFIG_SOURCEDIR
  find $CONFIG_INSTALLDIR -type f -iname 'config.guess' -exec cp -T -f ./config.guess {} \;
  find $CONFIG_INSTALLDIR -type f -iname 'config.sub' -exec cp -T -f ./config.sub {} \;
}
function getAndroidCMakeToolchain()
{
  ANDCMAKE_VER="android-cmake"
  ANDCMAKE_SOURCEDIR=$DEPS_SOURCE/$ANDCMAKE_VER
  ANDCMAKE_INSTALLDIR=$ANDCMAKE_SOURCEDIR/android.toolchain.cmake
  
  cd $DEPS_SOURCE
  if [ ! -d $ANDCMAKE_SOURCEDIR ]; then
    git clone https://github.com/taka-no-me/android-cmake.git
    cd $ANDCMAKE_SOURCEDIR
    git reset --hard 763b9f6ec43
  fi
  return $ANDCMAKE_INSTALLDIR;
}
function host_install_deps_toolchain()
{
  cd $DEPS_SOURCE

  # Android SDK
  if [ ! -d $ANDROID_SDK ]; then
    wget -c http://dl.google.com/android/android-sdk_r22.6.2-linux.tgz
    tar -xzf android-sdk_r22.6.2-linux.tgz
    
    # The user needs to accept a license, so we inject "y" as input. I'm not sure, whether this is legal.
    echo y | $ANDROID_SDK/tools/android update sdk -u --filter platform-tools,android-15
  fi
  
  # Android NDK
  if [ ! -d $ANDROID_NDK ]; then
    wget -c http://dl.google.com/android/ndk/android-ndk-r9d-linux-x86_64.tar.bz2
    tar -xjf android-ndk-r9d-linux-x86_64.tar.bz2
  fi
  set +e
  # Standalone posix toolchain
  $ANDROID_NDK/build/tools/make-standalone-toolchain.sh --ndk-dir=$ANDROID_NDK --platform=android-15 \
  --toolchain=arm-linux-androideabi-4.8 --system=linux-x86_64 --stl=gnustl --install-dir=$TOOLCHAIN
  set -e
}
function install_deps_toolchain()
{
  # Create libpthread.a and libz.a dummy, because many libraries are hardcoding -lpthread or -lz, but on Android pthread works out of box.
  touch dummy.c
  $TOOLCHAIN/bin/arm-linux-androideabi-gcc -o dummy.o -c dummy.c
  $TOOLCHAIN/bin/arm-linux-androideabi-ar cru $SYSROOT/usr/lib/libpthread.a dummy.o
  $TOOLCHAIN/bin/arm-linux-androideabi-ranlib $SYSROOT/usr/lib/libpthread.a
  $TOOLCHAIN/bin/arm-linux-androideabi-ar cru $SYSROOT/usr/lib/libz.a dummy.o
  $TOOLCHAIN/bin/arm-linux-androideabi-ranlib $SYSROOT/usr/lib/libz.a
  rm dummy.c
  rm dummy.o
  
  # Some dependencies use -lzlib to link zlib.
  cd $SYSROOT/usr/lib
  ln -s -f libz.a libzlib.a
}
function host_install_deps_boost()
{
  #This function will build bjam with host compiler
  BOOST_VER=1_55_0
  BOOST_DIR=boost_$BOOST_VER
  BOOST_BUILDDIR=$DEPS_BUILD/$BOOST_DIR/$BUILDDIR
  BOOST_ANDROID_SOURCEDIR=$DEPS_SOURCE/Boost-for-Android
  BOOST_SOURCEDIR=$BOOST_ANDROID_SOURCEDIR/$BOOST_DIR
    
  if [ ! -d $BOOST_ANDROID_SOURCEDIR ]; then
    cd $DEPS_SOURCE
    git clone https://github.com/MysticTreeGames/Boost-for-Android
    cd $BOOST_ANDROID_SOURCEDIR
    git reset --hard 8075d96cc9
  fi
  
  cd $BOOST_ANDROID_SOURCEDIR
  mkdir -p $BOOST_ANDROID_SOURCEDIR/logs
  ./build-android.sh --boost=1.55.0 --toolchain=arm-linux-androideabi-4.8 --download $ANDROID_NDK
  
  cd $BOOST_SOURCEDIR
  
  #build bjam
  ./bootstrap.sh
  mkdir -p $HOSTTOOLS/bin
  cp -f --dereference ./bjam $HOSTTOOLS/bin/bjam
}

function install_deps_boost()
{
  # This function will build boost using bjam from host.
  BOOST_VER=1_55_0
  BOOST_DIR=boost_$BOOST_VER
  BOOST_BUILDDIR=$DEPS_BUILD/$BOOST_DIR/$BUILDDIR
  BOOST_ANDROID_SOURCEDIR=$DEPS_SOURCE/Boost-for-Android
  BOOST_SOURCEDIR=$BOOST_ANDROID_SOURCEDIR/$BOOST_DIR

  cd $BOOST_ANDROID_SOURCEDIR
  
  # Apply patches to boost
  PATCH_BOOST_DIR=$BOOST_ANDROID_SOURCEDIR/patches/boost-${BOOST_VER}
  
  cp -f $SUPPORTDIR/android_user-config-boost-${BOOST_VER}.jam $BOOST_DIR/tools/build/v2/user-config.jam

  for DIR in $PATCH_BOOST_DIR; do
  
    if [ ! -d "$DIR" ]; then
      echo "Could not find directory '$DIR' while looking for patches"
      exit 1
    fi

    PATCHES=`(cd $DIR && ls *.patch | sort) 2> /dev/null`

    if [ -z "$PATCHES" ]; then
      echo "No patches found in directory '$DIR'"
      exit 1
    fi

    for PATCH in $PATCHES; do
      PATCH=`echo $PATCH | sed -e s%^\./%%g`
      SRC_DIR=$BOOST_SOURCEDIR
      PATCHDIR=`dirname $PATCH`
      PATCHNAME=`basename $PATCH`
      echo "Applying $PATCHNAME into $SRC_DIR/$PATCHDIR"
      cd $SRC_DIR
      set +e
      patch -N -p1 -b -r - < $DIR/$PATCH
      set -e
    done
  done

  cd $BOOST_SOURCEDIR
  export AndroidNDKRoot="$ANDROID_NDK"
  export NO_BZIP2=1

  cxxflags=""
  #CXXFLAG="-I$SYSROOT/usr/include -I$PREFIX/include -I$TOOLCHAIN/include/ -I$TOOLCHAIN/include/c++/4.8"
  for flag in $CXXFLAGS; do cxxflags="$cxxflags cxxflags=$flag"; done
  $HOSTTOOLS/bin/bjam -q -a toolset=gcc-androidR8e target-os=linux $cxxflags runtime-link=static link=static threading=multi --layout=system \
         --with-thread --with-date_time --with-chrono --with-system --prefix=$PREFIX install
}
function install_deps_ceguideps()
{
  CEGUIDEPS_VER=cegui-dependencies
  CEGUIDEPS_BUILDDIR=$DEPS_BUILD/$CEGUIDEPS_VER/$BUILDDIR/guest
  CEGUIDEPS_SOURCEDIR=$DEPS_SOURCE/$CEGUIDEPS_VER
  
  if [ ! -d $CEGUIDEPS_SOURCEDIR ]; then
    cd $DEPS_SOURCE
    hg clone https://bitbucket.org/cegui/cegui-dependencies -r 721921d
    cd $CEGUIDEPS_SOURCEDIR
    patch -N -p1 -r - < $SUPPORTDIR/android_fix-ceguideps.patch
  fi
  
  #-static will break the build
  LDFLAGS_SAVE="$LDFLAGS"
  export LDFLAGS=$(echo $LDFLAGS | sed "s/ -static / /g")
  
  mkdir -p $CEGUIDEPS_BUILDDIR
  cd $CEGUIDEPS_BUILDDIR
  cmake $CMAKE_CROSS_COMPILE $CMAKE_FLAGS -DCEGUI_BUILD_FREEIMAGE=false -DCEGUI_BUILD_FREETYPE2=false \
    -DCEGUI_BUILD_GLEW=false -DCEGUI_BUILD_GLFW=false -DCEGUI_BUILD_GLM=false -DCEGUI_BUILD_SILLY=false \
    -DCEGUI_BUILD_TOLUAPP=true -DCEGUI_BUILD_LUA=true -DCEGUI_BUILD_PCRE=true -DCEGUI_BUILD_EXPAT=true \
    CMAKE_C_COMPILER="$TOOLCHAIN/arm-linux-androideabi/bin/c++" $CEGUIDEPS_SOURCEDIR

  make $MAKE_FLAGS
  #make install
  
  #It seems make install is not installing, so we will copy it manually.
  cp -r -f $CEGUIDEPS_BUILDDIR/dependencies/lib/static/* $PREFIX/lib
  cp -r -f $CEGUIDEPS_BUILDDIR/dependencies/include/* $PREFIX/include
  
  export LDFLAGS="$LDFLAGS_SAVE"
}

function install_deps_sigc++()
{
  SIGCPP_VER="libsigc++-2.2.11"
  SIGCPP_BUILDDIR=$DEPS_BUILD/$SIGCPP_VER/$BUILDDIR
  SIGCPP_SOURCEDIR=$DEPS_SOURCE/$SIGCPP_VER
  
  cd $DEPS_SOURCE
  wget -c http://ftp.gnome.org/pub/GNOME/sources/libsigc++/2.2/$SIGCPP_VER.tar.xz
  tar -xJf $SIGCPP_VER.tar.xz
  updateAutotoolsToolchainDetection $SIGCPP_SOURCEDIR
  mkdir -p $SIGCPP_BUILDDIR
  cd $SIGCPP_BUILDDIR
  $SIGCPP_SOURCEDIR/configure $CONFIGURE_FLAGS
  make $MAKE_FLAGS
  make install
}

function install_deps_sdl()
{
  #SDL_VER="SDL2-2.0.3"
  SDL_VER="SDL"
  SDL_BUILDDIR=$DEPS_BUILD/$SDL_VER/$BUILDDIR
  SDL_SOURCEDIR=$DEPS_SOURCE/$SDL_VER
  
  cd $DEPS_SOURCE
  
  # Android with standalone toolchain will be supported in SDL 2.0.4
  if [ ! -d $SDL_SOURCEDIR ]; then
    hg clone http://hg.libsdl.org/SDL -r ace0e63268f3
    updateAutotoolsToolchainDetection $SDL_SOURCEDIR
  fi
  
  
  #wget -c http://www.libsdl.org/release/$SDL_VER.tar.gz
  #tar -xzf $SDL_VER.tar.gz
  mkdir -p $SDL_BUILDDIR
  cd $SDL_BUILDDIR
  $SDL_SOURCEDIR/configure $CONFIGURE_FLAGS \
  --disable-haptic --disable-audio
  make $MAKE_FLAGS
  make install
}
function install_deps_ogredeps()
{
  OGREDEPS_VER="ogredeps"
  OGREDEPS_BUILDDIR=$DEPS_BUILD/$OGREDEPS_VER/$BUILDDIR
  OGREDEPS_SOURCEDIR=$DEPS_SOURCE/$OGREDEPS_VER
  
  cd $DEPS_SOURCE
  
  if [ ! -d $OGREDEPS_SOURCEDIR ]; then
    hg clone https://bitbucket.org/cabalistic/ogredeps -r 27b96a4
    cd $OGREDEPS_SOURCEDIR
    patch -N -p1 -r - < $SUPPORTDIR/android_fix-ogredeps.patch
  fi

  mkdir -p $OGREDEPS_BUILDDIR
  cd $OGREDEPS_BUILDDIR
  
  cmake $CMAKE_CROSS_COMPILE $CMAKE_FLAGS -DOGREDEPS_BUILD_ZLIB=false $OGREDEPS_SOURCEDIR
  make $MAKE_FLAGS
  make install
  
  # Some dependencies link it as zzip instead of zziplib
  cd $PREFIX/lib
  ln -s -f libzziplib.a libzzip.a
}
function install_deps_glsloptimizer()
{
  OGRE_VER="glsl-optimizer"
  OGRE_BUILDDIR=$DEPS_BUILD/$OGRE_VER/$BUILDDIR
  OGRE_SOURCEDIR=$DEPS_SOURCE/$OGRE_VER
  
  cd $DEPS_SOURCE
  
  if [ ! -d $OGRE_SOURCEDIR ]; then
    hg clone https://bitbucket.org/sinbad/ogre -r 77f3a5a
    cd $OGRE_SOURCEDIR
    patch -N -p1 -r - < $SUPPORTDIR/android_fix-ogre.patch
  fi

  mkdir -p $OGRE_BUILDDIR
  cd $OGRE_BUILDDIR
  
  #export LDFLAGS="$LDFLAGS -landroid -llog -lEGL "

  cmake $CMAKE_CROSS_COMPILE $CMAKE_FLAGS  $OGRE_SOURCEDIR
  make $MAKE_FLAGS
  make install
}
function install_deps_ogre()
{
  OGRE_VER="ogre"
  OGRE_BUILDDIR=$DEPS_BUILD/$OGRE_VER/$BUILDDIR
  OGRE_SOURCEDIR=$DEPS_SOURCE/$OGRE_VER
  
  cd $DEPS_SOURCE
  
  if [ ! -d $OGRE_SOURCEDIR ]; then
    hg clone https://bitbucket.org/sinbad/ogre -r 77f3a5a
    cd $OGRE_SOURCEDIR
    patch -N -p1 -r - < $SUPPORTDIR/android_fix-ogre.patch
  fi

  mkdir -p $OGRE_BUILDDIR
  cd $OGRE_BUILDDIR
  
  cp -u ${ANDROID_NDK}/sources/android/cpufeatures/*.c $OGRE_SOURCEDIR/OgreMain/src/Android
  cp -u ${ANDROID_NDK}/sources/android/cpufeatures/*.h $OGRE_SOURCEDIR/OgreMain/include
  
  cmake $CMAKE_CROSS_COMPILE $CMAKE_FLAGS -DEGL_INCLUDE_DIR="" -DOPENGLES2_INCLUDE_DIR="" -DOGRE_LIB_SUFFIX=""\
    -DOGRE_BUILD_SAMPLES=false -DOGRE_STATIC=true -DOGRE_BUILD_TOOLS=false -DOGRE_UNITY_BUILD=true -DZLIB_PREFIX_PATH="$SYSROOT/usr"\
    -DANDROID_ABI=armeabi -DOGRE_DEPENDENCIES_DIR=$PREFIX $OGRE_SOURCEDIR
 
  make $MAKE_FLAGS
  make install
  
  #When static linking, we need to add all OGRE/* include directories to CFLAGS.
  OGREINCDIR=$PREFIX/include/OGRE
  cd $OGREINCDIR
  OGREINC=-I\${includedir}/OGRE/$(ls -1 -d */  | tr "\\n" ":" | sed 's=\(.*\)/:=\1=' | sed "s=/:= -I\${includedir}/OGRE/=g")
  sed -i "s=Cflags:=Cflags: $OGREINC=g" $PREFIX/lib/pkgconfig/OGRE.pc
  
  OGREINCDIR=$PREFIX/include/OGRE/Plugins
  cd $OGREINCDIR
  OGREINC=-I\${includedir}/OGRE/Plugins/$(ls -1 -d */  | tr "\\n" ":" | sed 's=\(.*\)/:=\1=' | sed "s=/:= -I\${includedir}/OGRE/Plugins/=g")
  sed -i "s=Cflags:=Cflags: $OGREINC=g" $PREFIX/lib/pkgconfig/OGRE.pc
  
  OGREINCDIR=$PREFIX/include/OGRE/RenderSystems
  cd $OGREINCDIR
  OGREINC=-I\${includedir}/OGRE/RenderSystems/$(ls -1 -d */  | tr "\\n" ":" | sed 's=\(.*\)/:=\1=' | sed "s=/:= -I\${includedir}/OGRE/RenderSystems/=g")
  sed -i "s=Cflags:=Cflags: $OGREINC=g" $PREFIX/lib/pkgconfig/OGRE.pc
}
function install_deps_libiconv()
{
  LIBICONV_VER="libiconv-1.14"
  LIBICONV_BUILDDIR=$DEPS_BUILD/$LIBICONV_VER/$BUILDDIR
  LIBICONV_SOURCEDIR=$DEPS_SOURCE/$LIBICONV_VER
  
  cd $DEPS_SOURCE
  wget -c http://ftp.gnu.org/pub/gnu/libiconv/$LIBICONV_VER.tar.gz
  tar -xzf $LIBICONV_VER.tar.gz
  updateAutotoolsToolchainDetection $LIBICONV_SOURCEDIR
  
  #-static will break the build
  LDFLAGS_SAVE="$LDFLAGS"
  LDFLAGS=$(echo $LDFLAGS | sed "s/ -static / /g")
  mkdir -p $LIBICONV_BUILDDIR
  cd $LIBICONV_BUILDDIR 
  $LIBICONV_SOURCEDIR/configure $CONFIGURE_FLAGS
  make  $MAKE_FLAGS
  make install
  LDFLAGS=$LDFLAGS_SAVE
}

function install_deps_cegui()
{
  CEGUI_VER="cegui"
  CEGUI_BUILDDIR=$DEPS_BUILD/$CEGUI_VER/$BUILDDIR
  CEGUI_SOURCEDIR=$DEPS_SOURCE/$CEGUI_VER
  
  cd $DEPS_SOURCE
  
  if [ ! -d $CEGUI_SOURCEDIR ]; then
    git clone https://github.com/ironsteel/cegui.git -b android-port
    cd $CEGUI_SOURCEDIR
    git reset --hard 577edcf46b
    patch -N -p1 -r - < $SUPPORTDIR/android_fix-cegui.patch
  fi

  #-static will break the build
  LDFLAGS_SAVE="$LDFLAGS"
  LDFLAGS=$(echo $LDFLAGS | sed "s/ -static / /g")
  
  mkdir -p $CEGUI_BUILDDIR
  cd $CEGUI_BUILDDIR
  #export LIBS="-Wl,--start-group -lboost_date_time -lboost_system -lboost_thread -lboost_chrono -lzzip -lFreeImage -lfreetype -llua -liconv -Wl,--end-group -lz -landroid -lc -lm -ldl -llog"
  cmake $CMAKE_CROSS_COMPILE $CMAKE_FLAGS $CEGUI_SOURCEDIR -DOGRE_LIB=$PREFIX/lib/libOgreMainStatic.a \
  -DCEGUI_BUILD_XMLPARSER_TINYXML=false -DCEGUI_SAMPLES_ENABLED=false -DCEGUI_BUILD_PYTHON_MODULES=false \
  -DBoost_LIBRARY_DIRS=$PREFIX/lib -DCEGUI_BUILD_STATIC_CONFIGURATION=true -DCEGUI_BUILD_LUA_GENERATOR=false \
  -DOGRE_LIBRARIES=""
  #cmake-gui .
  make -j1
  make install
  LDFLAGS=$LDFLAGS_SAVE
}

function install_deps_openal()
{
  OPENAL_VER="openal-soft"
  OPENAL_BUILDDIR=$DEPS_BUILD/$OPENAL_VER/$BUILDDIR
  OPENAL_SOURCEDIR=$DEPS_SOURCE/$OPENAL_VER
  
  cd $DEPS_SOURCE
  
  if [ ! -d $OPENAL_SOURCEDIR ]; then
  
    # Android only supports OpenSL.
    # OpenAL-soft is not supporting android, so we need to use a fork.
    git clone https://github.com/apportable/openal-soft.git -b openal-soft-1.15.1-android
    cd $OPENAL_SOURCEDIR
    git reset --hard 4c015951be11d
    patch -N -p1 -r - < $SUPPORTDIR/android_fix-openal.patch
  fi
  
  #-static will break the build, it seems everyone is using openal as dynamic lib on android, because of lgpl license.
  LDFLAGS_SAVE="$LDFLAGS"
  LDFLAGS=$(echo $LDFLAGS | sed "s/ -static / /g")
  
  mkdir -p $OPENAL_BUILDDIR
  cd $OPENAL_BUILDDIR
  cmake $CMAKE_CROSS_COMPILE $CMAKE_FLAGS $OPENAL_SOURCEDIR
  make $MAKE_FLAGS
  make install
  
  LDFLAGS="$LDFLAGS_SAVE"
}

function install_deps_freealut()
{
  FREEALUT_VER="freealut-1.1.0"
  FREEALUT_BUILDDIR=$DEPS_BUILD/$FREEALUT_VER/$BUILDDIR
  FREEALUT_SOURCEDIR=$DEPS_SOURCE/$FREEALUT_VER
  
  cd $DEPS_SOURCE
  # Creative's download page is down, so we need to use fedora mirror.
  wget -c http://pkgs.fedoraproject.org/repo/pkgs/freealut/$FREEALUT_VER.tar.gz/e089b28a0267faabdb6c079ee173664a/freealut-1.1.0.tar.gz
  tar -xzf freealut-1.1.0.tar.gz
  updateAutotoolsToolchainDetection $FREEALUT_SOURCEDIR

  #-static will break the build.
  LDFLAGS_SAVE="$LDFLAGS"
  LDFLAGS=$(echo $LDFLAGS | sed "s/ -static / /g")
  
  mkdir -p $FREEALUT_BUILDDIR
  cd $FREEALUT_BUILDDIR
  $FREEALUT_SOURCEDIR/configure $CONFIGURE_FLAGS
  make $MAKE_FLAGS
  make install

  LDFLAGS="$LDFLAGS_SAVE"
}

function install_deps_libcurl()
{
  LIBCURL_VER="curl"
  LIBCURL_BUILDDIR=$DEPS_BUILD/$LIBCURL_VER/$BUILDDIR
  LIBCURL_SOURCEDIR=$DEPS_SOURCE/$LIBCURL_VER
  
  cd $DEPS_SOURCE
  if [ ! -d $LIBCURL_SOURCEDIR ]; then
    git clone https://android.googlesource.com/platform/external/curl
  fi
  
  cd $LIBCURL_SOURCEDIR
  ./buildconf
  
  mkdir -p $LIBCURL_BUILDDIR
  cd $LIBCURL_BUILDDIR
  $LIBCURL_SOURCEDIR/configure $CONFIGURE_FLAGS
  make $MAKE_FLAGS
  make install

}

function host_install_deps_all()
{
  host_install_deps_toolchain
  host_install_deps_boost
}

function install_deps_all()
{
  install_deps_toolchain
  install_deps_boost
  install_deps_sigc++
  install_deps_libcurl
  install_deps_libiconv
  install_deps_openal
  install_deps_freealut
  install_deps_sdl
  install_deps_ceguideps
  install_deps_ogredeps
  install_deps_ogre
  install_deps_cegui
}

if [[ x"$HAMMERDIR" == x"" ]] ; then
  $HAMMERDIR="$PWD"
fi

# Set up hammer directory structure
export WORKDIR=$HAMMERDIR/work/android
export PREFIX=$WORKDIR/local
export TOOLCHAIN=$WORKDIR/toolchain
export DEPS_SOURCE=$WORKDIR/source
export DEPS_BUILD=$WORKDIR/build
export BUILDDIR=host
export SUPPORTDIR=$HAMMERDIR/support
export LOGDIR=$WORKDIR/logs
export HOSTTOOLS=$WORKDIR/host_tools

# Setup directories
mkdir -p $PREFIX
mkdir -p $DEPS_SOURCE
mkdir -p $DEPS_BUILD
mkdir -p $LOGDIR
mkdir -p $HOSTTOOLS/bin

# These are used by cmake to identify android kits
export ANDROID_SDK=$DEPS_SOURCE/android-sdk-linux
export ANDROID_NDK=$DEPS_SOURCE/android-ndk-r9d
export ANDROID_STANDALONE_TOOLCHAIN=$TOOLCHAIN
export NDK_TOOLCHAIN_VERSION=4.8

# Build tools with host compiler. Not all package requires tools.
if [ "$1" = "all" ] || [ "$1" = "toolchain" ] || [ "$1" = "boost" ] ; then
  echo Compiling $1 host tools
  host_install_deps_$1
  echo Succeed compiling $1 host tools
fi

# These are used by autoconfig for cross-compiling
export CROSS_COMPILER=arm-linux-androideabi
export SYSROOT=$TOOLCHAIN/sysroot
export CONFIGURE_CROSS_COMPILE="--host=${CROSS_COMPILER} --prefix=${PREFIX}"

# Set android toolchain to the beginning of PATH, so that any call to "gcc" or "g++" will end up into android toolchain.
export PATH=$TOOLCHAIN/bin:$TOOLCHAIN/arm-linux-androideabi/bin:$ANDROID_SDK/platform-tools:$ANDROID_SDK/tools:$ANDROID_NDK:$HOSTTOOLS/bin:$PATH

# Set up prefix path properly
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
export ACLOCAL_ARGS="$ACLOCAL_ARGS -I $PREFIX/share/aclocal"
export CONFIGURE_FLAGS="$CONFIGURE_CROSS_COMPILE --enable-static --disable-dynamic --disable-rpath"
export BUILDDIR=android

# Set up compiler/linker
# Optimization flags
export CFLAGS="-g -Os -fno-omit-frame-pointer"
# Select ARM instruction set and min VFP version. softfp ABI means that it will not use 
# VFP registers through ABI calls (softfp and hardfp has incompatible ABI and can't be linked together).
export CFLAGS="-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp -mthumb $CFLAGS"
#Disable warning spam from boost
export CFLAGS="-Wno-unused-local-typedefs -Wno-unused-variable"
# The aliasing and pic is required, while inline-limit speeds up builds.
export CFLAGS="-fno-strict-aliasing -fpic -finline-limit=64 $CFLAGS"
# Macros that should be set to detect android/arm.
export CFLAGS="-D__ANDROID__ -DANDROID -D__arm__ $CFLAGS"
# Required for threading.
export CFLAGS="-D_GLIBCXX__PTHREADS -D_REENTRANT $CFLAGS"
# Required for boost
export CFLGAS="-D__GLIBC__"
# Required if not compiling through toolchain.
export CFLAGS="--sysroot=$SYSROOT $CFLAGS"
# Includes
export CFLAGS="-I$TOOLCHAIN/include/c++/4.8/arm-linux-androideabi/armv7-a/thumb $CFLAGS"

export CPATH="$TOOLCHAIN/include/c++/4.8/arm-linux-androideabi/armv7-a/thumb"
export CPATH="$CPATH:$TOOLCHAIN/include/c++/4.8"
export CPATH="$CPATH:$SYSROOT/usr/include"
export CPATH="$CPATH:$PREFIX/include"

# Transform CPATH into -I... compiler flags
INCFLAGS=-I$(echo $CPATH | sed "s/:/ -I/g")
export CFLAGS="$CFLAGS $INCFLAGS"

export CPPFLAGS="$CFLAGS"
export CXXFLAGS="$CFLAGS -frtti -fexceptions"
export LDFLAGS="-march=armv7-a -Wl,--fix-cortex-a8 -Wl,--no-undefined"

#Tell libtool to only link static libs.
export LDFLAGS="$LDFLAGS -static"

export LIBRARY_PATH="$TOOLCHAIN/arm-linux-androideabi/lib/armv7-a/thumb"
export LIBRARY_PATH="$LIBRARY_PATH:$TOOLCHAIN/lib/gcc/arm-linux-androideabi/4.8/armv7-a/thumb"
export LIBRARY_PATH="$LIBRARY_PATH:$SYSROOT/usr/lib"
export LIBRARY_PATH="$LIBRARY_PATH:$PREFIX/lib"
export LD_LIBRARY_PATH="$LIBRARY_PATH"

# Transform LIBRARY_PATH into -L... linker flags
LIBFLAGS=-L$(echo $LIBRARY_PATH | sed "s/:/ -L/g")
export LDFLAGS="$LDFLAGS $LIBFLAGS"

echo "LDFLAGS=$LDFLAGS"
echo "CFLAGS=$CFLAGS"

# Get common ancestor prefix, so that system paths like /usr/lib will be ignored by cmake
export CMAKE_ROOT_PATH=`printf "%s\n%s\n" "$PREFIX" "$TOOLCHAIN" | sed -e 'N;s/^\(.*\).*\n\1.*$/\1/'`

# Set up cmake flags required for cross-compiling
export CMAKE_CROSS_COMPILE="-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_C_COMPILER=$TOOLCHAIN/arm-linux-androideabi/bin/gcc \
  -DCMAKE_FIND_ROOT_PATH=$CMAKE_ROOT_PATH -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_MAKE_PROGRAM=make -DANDROID=true -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_INSTALL_PREFIX=$PREFIX"
#export CMAKE_CROSS_COMPILE="-DCMAKE_TOOLCHAIN_FILE=$(getAndroidCMakeToolchain) -DCMAKE_FIND_ROOT_PATH=$CMAKE_ROOT_PATH -DCMAKE_INSTALL_PREFIX=$PREFIX"

#TODO: Set up logs, but for now it is easier to debug without logs.
if [ "$1" = "all" ] || [ "$1" = "toolchain" ] || [ "$1" = "sigc++" ] || [ "$1" = "openal" ] || [ "$1" = "freealut" ] || [ "$1" = "libcurl" ] || [ "$1" = "libiconv" ] || 
   [ "$1" = "boost" ] || [ "$1" = "sdl" ] || [ "$1" = "ogredeps" ] || [ "$1" = "ogre" ] || [ "$1" = "ceguideps" ] || [ "$1" = "cegui" ] ; then
  echo Compiling $1
  install_deps_$1
  echo Completed successfully!
else
  printf >&2 'Unknown target: %s\n' "$1"
  exit 1
fi
