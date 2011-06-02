#!/bin/bash

set -e

export PREFIX="$PWD/work/local"
export PATH="$PREFIX/bin:$PATH"
export CPATH="$PREFIX/include:$CPATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:/mingw/lib/pkgconfig:/lib/pkgconfig:$PKG_CONFIG_PATH"
export ACLOCAL_ARGS="$ACLOCAL_ARGS -I $PREFIX/share/aclocal"
export CONFIGURE_EXTRA_FLAGS="--enable-shared --disable-static"
export MAKEOPTS="-j4"
LOGDIR=$PWD/work/logs/deps
BUILDDEPS=$PWD/work/build/deps
PACKAGEDIR=$BUILDDEPS/packages
DLDIR=$BUILDDEPS/downloads
LOCKDIR=$BUILDDEPS/locks

mkdir -p $LOGDIR
mkdir -p $BUILDDEPS
mkdir -p $PACKAGEDIR
mkdir -p $DLDIR
mkdir -p $LOCKDIR
mkdir -p $PREFIX/bin
mkdir -p $PREFIX/lib
mkdir -p $PREFIX/include

cd $PACKAGEDIR

#this is needed, because tar and bsdtar makes segfaults sometimes.
function extract(){
	if [[ $1 == *.tar* ]]; then
		7za x -y -so $1 | 7za x -y -si -ttar > /dev/null
	else
		7za x -y $1 > /dev/null
	fi
}
function printc(){
	echo -e "\033[33m$1\033[0m"
}
#install without hacks
#$1: URL
#$2: archive filename to detect http redirection problems.
function installpackage(){
	PKGNAME=$(echo "$2" | sed "s/\.[^\.]*$//;s/\.tar[^\.]*$//") 
	PKGLOGDIR="$LOGDIR/$PKGNAME"
	PKGLOCKFILE="$LOCKDIR/${PKGNAME}_installed.lock"
	if [ ! -f $PKGLOCKFILE ]; then
		printc "Installing $PKGNAME..."
		mkdir -p $PKGLOGDIR
		printc "    Downloading..."
		wget -q -c -P $DLDIR $1
		printc "    Extracting..."
		extract $DLDIR/$2 2> $PKGLOGDIR/extract.log
		mkdir -p $PKGNAME/mingw_build
		cd $PKGNAME
		if [ ! -f "configure" ] ; then
			printc "    Running autogen..."
			NOCONFIGURE=1 ./autogen.sh > $PKGLOGDIR/autogen.log
		fi
		cd mingw_build
		printc "    Running configure..."
		../configure --prefix=$PREFIX $CONFIGURE_EXTRA_FLAGS > $PKGLOGDIR/configure.log
		printc "    Building..."
		make $MAKEOPTS > $PKGLOGDIR/build.log
		
		printc "    Installing..."
		make install > $PKGLOGDIR/install.log
		cd ../..
		touch $PKGLOCKFILE
	fi
}

#install 7za
#hacks:
#	this is needed, because tar and bsdtar makes segfaults sometimes.
PKGLOCKFILE="$LOCKDIR/7za_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	printc "Installing 7za..."
	mkdir -p 7za
	cd 7za
	wget -q -c -P $DLDIR http://downloads.sourceforge.net/sevenzip/7za920.zip
	bsdtar -xf $DLDIR/7za920.zip
	cp ./7za.exe $PREFIX/bin/7za.exe
	cd ..
	touch $PKGLOCKFILE
fi

#install rsync
#maybe we should host this file
#wget -c -P $DLDIR http://download1039.mediafire.com/p2h9ja9uzvtg/g35fh308hmdklz5/rsync-3.0.8.tar.lzma
#wget -c -P $DLDIR http://k002.kiwi6.com/hotlink/w8nv7zl9qh/rsync_3_0_8_tar.lzma
mkdir -p rsync
cd rsync
wget -c -P $DLDIR http://sajty.elementfx.com/rsync-3.0.8.tar.lzma
bsdtar -xf $DLDIR/rsync-3.0.8.tar.lzma
cp rsync.exe $PREFIX/bin/rsync.exe
cd ..

#install glib
FILENAME="glib-2.28.7.tar.bz2"
installpackage "http://ftp.gnome.org/pub/gnome/sources/glib/2.28/$FILENAME" "$FILENAME"

#install pkg-config:
export GLIB_CFLAGS="-I$PREFIX/include/glib-2.0 -I$PREFIX/lib/glib-2.0/include -mms-bitfields"
export GLIB_LIBS="-L$PREFIX/lib/ -lglib-2.0 -lintl " 
FILENAME="pkg-config-0.26.tar.gz"
installpackage "http://pkgconfig.freedesktop.org/releases/$FILENAME" "$FILENAME"

#install freeimage
wget -c -P $DLDIR http://downloads.sourceforge.net/freeimage/FreeImage3150.zip
bsdtar -xf $DLDIR/FreeImage3150.zip
cd FreeImage
make -f Makefile.minGW FREEIMAGE_LIBRARY_TYPE=STATIC DLLTOOLFLAGS="" $MAKEOPTS
cp Dist/FreeImage.a $PREFIX/lib/libFreeImage.a
cp Dist/FreeImage.h $PREFIX/include/FreeImage.h
cd ..


export CFLAGS="-O3 -msse2 -ffast-math -mthreads -DNDEBUG -I$PREFIX/include $CFLAGS"
#without -msse2 ogre is not building
export CXXFLAGS="-O3 -msse2 -ffast-math -mthreads -DNDEBUG -I$PREFIX/include $CXXFLAGS"

#install cmake
wget -c -P $DLDIR http://www.cmake.org/files/v2.8/cmake-2.8.4.tar.gz
bsdtar -xf $DLDIR/cmake-2.8.4.tar.gz
cd cmake-2.8.4
./configure --prefix=$PREFIX
make $MAKEOPTS
cp bin/cmake.exe $PREFIX/bin/cmake.exe
make install
cd ..

#install zziplib
FILENAME="zziplib-0.13.60.tar.bz2"
installpackage "http://sourceforge.net/projects/zziplib/files/zziplib13/0.13.60/$FILENAME/download" "$FILENAME"

#install freetype
FILENAME="freetype-2.4.4.tar.bz2"
installpackage "http://sourceforge.net/projects/freetype/files/freetype2/2.4.4/$FILENAME/download" "$FILENAME"

#install SDL
FILENAME="SDL-1.2.14.tar.gz"
installpackage "http://www.libsdl.org/release/$FILENAME" "$FILENAME"
#install libCURL
FILENAME="curl-7.21.6.tar.bz2"
installpackage "http://curl.haxx.se/download/$FILENAME" "$FILENAME"

#install pcre
FILENAME="pcre-8.12.tar.bz2"
installpackage "http://sourceforge.net/projects/pcre/files/pcre/8.12/$FILENAME/download" "$FILENAME"

#install sigc++
#hacks:
#	7za is not supporting PAX, need to use bsdtar
PKGNAME="libsigc++-2.2.9"
PKGLOGDIR="$LOGDIR/$PKGNAME"
PKGLOCKFILE="$LOCKDIR/${PKGNAME}_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	printc "Installing $PKGNAME..."
	mkdir -p $PKGLOGDIR
	printc "    Downloading..."
	wget -q -c -P $DLDIR http://ftp.gnome.org/pub/GNOME/sources/libsigc++/2.2/$PKGNAME.tar.gz
	printc "    Extracting..."
	bsdtar -xf  $DLDIR/$PKGNAME.tar.gz
	mkdir -p $PKGNAME/mingw_build
	cd $PKGNAME/mingw_build
	printc "    Running configure..."
	../configure --prefix=$PREFIX $CONFIGURE_EXTRA_FLAGS > $PKGLOGDIR/configure.log
	printc "    Building..."
	make $MAKEOPTS > $PKGLOGDIR/build.log
	
	printc "    Installing..."
	make install > $PKGLOGDIR/install.log
	cd ../..
	touch $PKGLOCKFILE
fi

#install boost
#bjam generated in msys is not working, we need prebuilt bjam.
wget -c -P $DLDIR http://sourceforge.net/projects/boost/files/boost-jam/3.1.18/boost-jam-3.1.18-1-ntx86.zip/download
bsdtar -xf $DLDIR/boost-jam-3.1.18-1-ntx86.zip
wget -c -P $DLDIR http://sourceforge.net/projects/boost/files/boost/1.46.1/boost_1_46_1.tar.bz2/download
bsdtar -xf $DLDIR/boost_1_46_1.tar.bz2
ln -s $PWD/boost-jam-3.1.18-1-ntx86/bjam.exe $PWD/boost_1_46_1/bjam
cd boost_1_46_1
./bjam --with-thread --with-date_time --stagedir=$PREFIX --layout=system variant=release link=shared toolset=gcc
#"./bjam install" is not working in msys, we need to install the headers manually.
cp -r boost $PREFIX/include
cd ..
mv $PREFIX/lib/libboost_date_time.dll $PREFIX/bin/libboost_date_time.dll
mv $PREFIX/lib/libboost_thread.dll $PREFIX/bin/libboost_thread.dll

#install lua
wget -c -P $DLDIR http://www.lua.org/ftp/lua-5.1.4.tar.gz
bsdtar -xf $DLDIR/lua-5.1.4.tar.gz
cd lua-5.1.4
make mingw $MAKEOPTS
make install INSTALL_TOP=$PREFIX
cd ..

#install tolua++
wget -c -P $DLDIR http://www.codenix.com/~tolua/tolua++-1.0.93.tar.bz2
bsdtar -xf $DLDIR/tolua++-1.0.93.tar.bz2
cd tolua++-1.0.93
#tolua uses scons, which needs python, which is big.
#note: creating makefile would be better
cp include/tolua++.h $PREFIX/include/tolua++.h
cd src/lib
gcc $CFLAGS -c -I$PREFIX/include -L$PREFIX/lib *.c
ar cq libtolua++.a *.o
cp libtolua++.a $PREFIX/lib/libtolua++.a
cd ../bin
gcc $CFLAGS $LDFLAGS -o tolua++ -I$PREFIX/include -L$PREFIX/lib -mwindows tolua.c toluabind.c -ltolua++ -llua
cp tolua++.exe $PREFIX/bin/tolua++.exe
cd ../../..

#install openal-soft
wget -c -P $DLDIR http://kcat.strangesoft.net/openal-releases/openal-soft-1.13.tar.bz2
bsdtar -xf $DLDIR/openal-soft-1.13.tar.bz2
cd openal-soft-1.13
cd build
cmake -DCMAKE_INSTALL_PREFIX=$PREFIX -G"MSYS Makefiles" ..
make all $MAKEOPTS
make install
cd ../..

#install freealut
wget -c -P $DLDIR http://connect.creativelabs.com/openal/Downloads/ALUT/freealut-1.1.0-src.zip
bsdtar -xf $DLDIR/freealut-1.1.0-src.zip
cd freealut-1.1.0-src
./autogen.sh
./configure --prefix=$PREFIX $CONFIGURE_EXTRA_FLAGS
make CFLAGS="$CFLAGS `pkg-config --cflags openal`" LDFLAGS="$LDFLAGS `pkg-config --libs openal`" $MAKEOPTS
make install
cd ..

#install CG
cp -r "$CG_INC_PATH" $PREFIX
cp "$CG_BIN_PATH/cg.dll" $PREFIX/bin/cg.dll
pexports $PREFIX/bin/cg.dll | sed "s/^_//" > libCg.def
dlltool --add-underscore -d libCg.def -l $PREFIX/lib/libCg.a
rm libCg.def

#install Ogre3D
wget -c -P $DLDIR http://sourceforge.net/projects/ogre/files/ogre/1.7/ogre_src_v1-7-3.tar.bz2/download
7za x -y $DLDIR/ogre_src_v1-7-3.tar.bz2
7za x -y ogre_src_v1-7-3.tar
rm ogre_src_v1-7-3.tar
cd ogre_src_v1-7-3
mkdir -p build
cd build
cmake --with-gui=win32 --with-platform=win32 --enable-direct3d -DCMAKE_INSTALL_PREFIX=$PREFIX -G"MSYS Makefiles" -DOGRE_INSTALL_DEPENDENCIES=false \
-DOGRE_BUILD_SAMPLES=false -DOGRE_BUILD_PLUGIN_BSP=false -DOGRE_BUILD_PLUGIN_OCTREE=false -DOGRE_BUILD_PLUGIN_PCZ=false -DOGRE_BUILD_COMPONENT_RTSHADERSYSTEM=false ..
make all $MAKEOPTS
make install
cp -r $PREFIX/bin/RelWithDebInfo/* $PREFIX/bin
cp -r $PREFIX/lib/RelWithDebInfo/* $PREFIX/lib
cd ../..

#install CEGUI
wget -c -P $DLDIR http://sourceforge.net/projects/crayzedsgui/files/CEGUI%20Mk-2/0.7.5/CEGUI-0.7.5.tar.gz/download
bsdtar -xf $DLDIR/CEGUI-0.7.5.tar.gz
cd CEGUI-0.7.5
./configure --prefix=$PREFIX --disable-samples --disable-opengl-renderer --disable-irrlicht-renderer --disable-xerces-c --disable-libxml --disable-expat --disable-directfb-renderer \
--enable-freeimage --enable-ogre-renderer --enable-lua-module --enable-external-toluapp \
Ogre_CFLAGS="-I$PREFIX/include -I$PREFIX/include/OGRE" Ogre_LIBS="-lOgreMain" \
FreeImage_CFLAGS="-DUSE_FREEIMAGE_LIBRARY -I$PREFIX/include" FreeImage_LIBS="-lFreeImage" \
Lua_CFLAGS="-I$PREFIX/include" Lua_LIBS="-llua" \
toluapp_CFLAGS="-I$PREFIX/include" toluapp_LIBS="-ltolua++" \
MINGW32_BUILD=true CEGUI_BUILD_LUA_MODULE_UNSAFE=true CEGUI_BUILD_TOLUAPPLIB=true \
$CONFIGURE_EXTRA_FLAGS
make $MAKEOPTS
make install
cd ..

