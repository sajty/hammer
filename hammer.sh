#!/bin/bash

set -e

export HAMMERDIR=$PWD
export WORKDIR=$HAMMERDIR/work
export PREFIX=$WORKDIR/local
export SOURCE=$WORKDIR/build/worldforge
export DEPS_SOURCE=$WORKDIR/build/deps
export MAKEOPTS="-j3"
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH
export BUILDDIR=`uname -m`

# setup directories
mkdir -p $PREFIX
mkdir -p $DEPS_SOURCE
mkdir -p $SOURCE

# Log Directory
LOGDIR=$WORKDIR/logs
mkdir -p $LOGDIR

# Output redirect logs
AUTOLOG=autogen.log     # Autogen output
CONFIGLOG=config.log    # Configure output
MAKELOG=build.log      # Make output
INSTALLLOG=install.log # Install output

# Dependencies
CEGUI=CEGUI-0.7.5
CEGUI_DOWNLOAD=CEGUI-0.7.5.tar.gz
OGRE=ogre_1_7_3
OGRE_DOWNLOAD=ogre_src_v1-7-3.tar.bz2

CONFIGURE_EXTRA_FLAGS=""
CMAKE_EXTRA_FLAGS=""

if [ x$MSYSTEM = x"MINGW32" ] ; then
	export CONFIGURE_EXTRA_FLAGS="--enable-shared --disable-static"
	export CXXFLAGS="-O3 -msse2 -ffast-math -mthreads $CXXFLAGS"
	export PATH="$PREFIX/bin:$PATH"
	export CPATH="$PREFIX/include:$CPATH"
	export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
	export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
	export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:/usr/local/lib/pkgconfig:/mingw/lib/pkgconfig:/lib/pkgconfig:$PKG_CONFIG_PATH"
fi


function buildwf()
{
    mkdir -p $LOGDIR/$1

    cd $SOURCE/$1
    if [ ! -f "configure" ] ; then
      echo "  Running autogen..."
      NOCONFIGURE=1 ./autogen.sh > $LOGDIR/$1/$AUTOLOG
    fi

    mkdir -p $BUILDDIR
    cd $BUILDDIR
    if [ ! -f "Makefile" ] ; then
      echo "  Running configure..."
      ../configure --prefix=$PREFIX $CONFIGURE_EXTRA_FLAGS > $LOGDIR/$1/$CONFIGLOG
    fi

    echo "  Building..."
    make $MAKEOPTS > $LOGDIR/$1/$MAKELOG
    echo "  Installing..."
    make install > $LOGDIR/$1/$INSTALLLOG
}

function checkoutwf()
{
  if [ ! -d $1 ]; then
    git clone git://github.com/worldforge/$1.git
  else
    cd $1 && git remote set-url origin git://github.com/worldforge/$1.git && git fetch && git rebase origin/master && cd ..
  fi
}

function cyphesis_post_install()
{
  cd $PREFIX/bin

  # Rename real cyphesis binary to cyphesis.bin
  mv cyphesis cyphesis.bin

  # Install our cyphesis.in script as cyphesis
  cp $HAMMERDIR/cyphesis.in cyphesis
  chmod +x cyphesis  
}

function show_help()
{
  if [ $1 = "main" ] ; then
    echo "Script for automating the process of installing dependencies" 
    echo "and compiling Worldforge in a self contained environment."
    echo ""
    echo "Usage: hammer.sh <command> <arguments>"
    echo "Commands:"
    echo "  install-deps -  install all 3rd party dependencies"
    echo "  checkout     -  fetch worldforge source (libraries, clients)"
    echo "  build        -  build the sources and install in environment"
    echo "  clean        -  delete build directory so a fresh build can be performed"
    echo ""
    echo "For more help, type: hammer.sh help <command>"
  elif [ $1 = "install-deps" ] ; then
    echo "Install all 3rd party dependencies into build environment."
    echo ""
    echo "Usage: hammer.sh install-deps <dependency to install>"
    echo "Dependencies Available:"
    echo "  all      -  install all dependencies listed below"
    echo "  cegui    -  a free library providing windowing and widgets for 
                        graphics APIs / engines"
    echo "  ogre     -  3D rendering engine"
	echo "Hint: build ogre first then cegui"
  elif [ $1 = "checkout" ] ; then
    echo "Fetch latest source code for worldforge libraries and clients."
    echo ""
    echo "Usage: hammer.sh checkout"
  elif [ $1 = "build" ] ; then
    echo "Build the sources and install in environment."
    echo ""
    echo "Usage: hammer.sh build <target> \"<makeopts>\""
    echo "Available targets:"
    echo "  libs  -  build libraries only"
    echo "  ember -  build ember only"
    echo "  cyphesis - build cyphesis server only"
    echo "makeopts [optional] - options to pass into make"
    echo ""
    echo "Hint: after a checkout use 'all'. To rebuild after changing code"
    echo "only in Ember, use 'ember'. Will build much quicker!"
  elif [ $1 = "clean" ] ; then
    echo "Clean out build files of a project."
    echo ""
    echo "Usage: hammer.sh clean <target>"
    echo "Targets:"
    echo "  cegui, ogre, libs/<name>, clients/<name>, servers/<name>"
  else
    echo "No help page found!"
  fi
}

# Show main help page if no arguments given
if [ $# -eq 0 ] ; then
  show_help "main"

# If help command given, show help page
elif [ $1 = "help" ] ; then
  if [ $# -eq 2 ] ; then
    show_help $2
  else
    show_help "main"
  fi

mkdir -p $PREFIX $SOURCE $DEPS_SOURCE

# Dependencies install
elif [ $1 = "install-deps" ] ; then
  if [ x$MSYSTEM = x"MINGW32" ] ; then
    SCRIPTDIR=`dirname "$0"`
    $SCRIPTDIR/mingw_install_deps.sh
    exit 0
  fi
  if [ $# -ne 2 ] ; then
    echo "Missing required parameter!"
    show_help "install-deps"
    exit 1
  fi

  echo "Installing deps..."

  # Create deps log directory
  mkdir -p $LOGDIR/deps

  # Ogre3D
  if [ $2 = "all" ] || [ $2 = "ogre" ] ; then
    echo "  Installing Ogre..."
    mkdir -p $LOGDIR/deps/ogre
    cd $DEPS_SOURCE
    if [ ! -d $OGRE ]; then
      echo "  Downloading..."
      wget -c http://downloads.sourceforge.net/sourceforge/ogre/$OGRE_DOWNLOAD
      mkdir -p $OGRE
      cd $OGRE
      tar -xjf ../$OGRE_DOWNLOAD
    fi
    cd $DEPS_SOURCE/$OGRE/`ls $DEPS_SOURCE/$OGRE`
    mkdir -p $BUILDDIR
    cd $BUILDDIR
    echo "  Configuring..."
	OGRE_EXTRA_FLAGS=""
    cmake .. -DCMAKE_INSTALL_PREFIX="$PREFIX" -DOGRE_BUILD_SAMPLES=false $OGRE_EXTRA_FLAGS $CMAKE_EXTRA_FLAGS > $LOGDIR/deps/ogre/$CONFIGLOG
    echo "  Building..."
    make $MAKEOPTS > $LOGDIR/deps/ogre/$MAKELOG
    echo "  Installing..."
    make install > $LOGDIR/deps/ogre/$INSTALLLOG
    echo "  Done."
  fi

  # CEGUI
  if [ $2 = "all" ] || [ $2 = "cegui" ] ; then
    echo "  Installing CEGUI..."
    mkdir -p $LOGDIR/deps/CEGUI    # create CEGUI log directory
    cd $DEPS_SOURCE
    if [ ! -d $CEGUI ] ; then
      echo "  Downloading..."
      wget -c http://downloads.sourceforge.net/sourceforge/crayzedsgui/$CEGUI_DOWNLOAD
      tar zxvf $CEGUI_DOWNLOAD
    fi
    cd $CEGUI
    mkdir -p $BUILDDIR
    cd $BUILDDIR
    echo "  Configuring..."
    ../configure --prefix=$PREFIX  --disable-samples --disable-opengl-renderer --disable-irrlicht-renderer --disable-xerces-c --disable-libxml --disable-expat --disable-directfb-renderer $CONFIGURE_EXTRA_FLAGS > $LOGDIR/deps/CEGUI/$CONFIGLOG
    echo "  Building..."
    make $MAKEOPTS > $LOGDIR/deps/CEGUI/$MAKELOG
    echo "  Installing..."
    make install > $LOGDIR/deps/CEGUI/$INSTALLLOG
    echo "  Done."
  fi

  echo "Install Done."

# Source checkout
elif [ $1 = "checkout" ] ; then
  echo "Fetching sources..."

  mkdir -p $SOURCE/libs
  cd $SOURCE/libs

  # Varconf
  echo "  Varconf..."
  checkoutwf "varconf"
  echo "  Done."

  # Atlas-C++
  echo "  Atlas-C++..."
  checkoutwf "atlas-cpp"
  echo "  Done."

  # Skstream
  echo "  Skstream..."
  checkoutwf "skstream"
  echo "  Done."

  # Wfmath
  echo "  Wfmath..."
  checkoutwf "wfmath"
  echo "  Done."

  # Eris
  echo "  Eris..."
  checkoutwf "eris"
  echo "  Done."

  # Libwfut
  echo "  Libwfut..."
  checkoutwf "libwfut"
  echo "  Done."

  # Mercator
  echo "  Mercator..."
  checkoutwf "mercator"
  echo "  Done."

  # Ember client
  echo "  Ember client..."
  mkdir -p $SOURCE/clients
  cd $SOURCE/clients
  checkoutwf "ember"
  echo "  Done."

  # Cyphesis
  echo "  Cyphesis..."
  mkdir -p $SOURCE/servers
  cd $SOURCE/servers
  checkoutwf "cyphesis"
  echo "  Done."

  echo "Checkout Done."

# Build source
elif [ $1 = "build" ] ; then
  if [ $# -lt 2 ] ; then
    echo "Missing required parameter!"
    show_help "build"
    exit 1
  fi

  # Check for make options
  if [ $# -ge 3 ] ; then
    MAKEOPTS=$3
  fi

  echo "Building sources..."

  # Build libraries
  if [ $2 = "libs" ] || [ $2 = "all" ] ; then

  # Varconf
  echo "  Varconf..."
  buildwf "libs/varconf"
  echo "  Done."

  # Skstream
  echo "  Skstream..."
  buildwf "libs/skstream"
  echo "  Done."

  # Wfmath
  echo "  Wfmath..."
  buildwf "libs/wfmath"
  echo "  Done."

  # Atlas-C++
  echo "  Atlas-C++..."
  buildwf "libs/atlas-cpp"
  echo "  Done."

  # Mercator
  echo "  Mercator..."
  buildwf "libs/mercator"
  echo "  Done."

  # Eris
  echo "  Eris..."
  buildwf "libs/eris"
  echo "  Done."

  # Libwfut
  echo "  Libwfut..."
  buildwf "libs/libwfut"
  echo "  Done."

  fi

  if [ $2 = "ember" ] || [ $2 = "all" ] ; then

  # Ember client
  echo "  Ember client..."
  buildwf "clients/ember"
  echo "  Done."

  if command -v rsync &> /dev/null; then
    echo "Fetching media..."
    cd $SOURCE/clients/ember/$BUILDDIR
    make devmedia
    echo "Media fetched."
  else
    echo "Rsync not found, skipping fetching media. You will need to download and install it yourself."
  fi

  fi

  if [ $2 = "cyphesis" ] || [ $2 = "all" ] ; then

  # Cyphesis
  echo "  Cyphesis..."
  buildwf "servers/cyphesis"
  cyphesis_post_install
  echo "  Done."

  fi

  echo "Build Done."

elif [ $1 = "clean" ] ; then
  if [ $# -ne 2 ] ; then
    echo "Missing required parameter!"
    show_help "clean"
    exit 1
  fi

  # Delete build directory
  if [ $2 = "cegui" ] ; then
    rm -rf $DEPS_SOURCE/$CEGUI/$BUILDDIR
  elif [ $2 = "ogre" ] ; then
    rm -rf $DEPS_SOURCE/$OGRE/ogre/$BUILDDIR
  else
    rm -rf $SOURCE/$2/$BUILDDIR
  fi

else
  echo "Invalid command!"
  show_help "main"
fi
