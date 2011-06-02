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
#install package without hacks
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
PKGLOCKFILE="$LOCKDIR/rsync_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	printc "Installing rsync..."
	mkdir -p rsync
	cd rsync
	wget -q -c -P $DLDIR http://sajty.elementfx.com/rsync-3.0.8.tar.lzma
	extract $DLDIR/rsync-3.0.8.tar.lzma 2> /dev/null
	cp rsync.exe $PREFIX/bin/rsync.exe
	cd ..
	touch $PKGLOCKFILE
fi
#install glib
FILENAME="glib-2.28.7.tar.bz2"
installpackage "http://ftp.gnome.org/pub/gnome/sources/glib/2.28/$FILENAME" "$FILENAME"

#install pkg-config:
export GLIB_CFLAGS="-I$PREFIX/include/glib-2.0 -I$PREFIX/lib/glib-2.0/include -mms-bitfields"
export GLIB_LIBS="-L$PREFIX/lib/ -lglib-2.0 -lintl " 
FILENAME="pkg-config-0.26.tar.gz"
installpackage "http://pkgconfig.freedesktop.org/releases/$FILENAME" "$FILENAME"

#install freeimage
#hacks:
#	you need to force mingw makefile, or it will use gnu makefile.
#	Do not set *FLAGS or it will fail.
#	FREEIMAGE_LIBRARY_TYPE needs to be static or it will make .lib instead of .a file.
#	DLLTOOLFLAGS needs to be "" or ogre will get linker errors.
#	it will try to install .lib, so we need to install it manually
#	it needs python to build documentation. You can't disable documentation.
PKGNAME="FreeImage"
PKGLOGDIR="$LOGDIR/$PKGNAME"
PKGLOCKFILE="$LOCKDIR/${PKGNAME}_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	printc "Installing $PKGNAME..."
	mkdir -p $PKGLOGDIR
	printc "    Downloading..."
	wget -q -c -P $DLDIR http://downloads.sourceforge.net/freeimage/FreeImage3150.zip
	printc "    Extracting..."
	extract $DLDIR/FreeImage3150.zip 2> $PKGLOGDIR/extract.log
	cd $PKGNAME
	printc "    Building..."
	make -f Makefile.minGW FREEIMAGE_LIBRARY_TYPE=STATIC DLLTOOLFLAGS="" > $PKGLOGDIR/build.log
	printc "    Installing..."
	cp Dist/FreeImage.a $PREFIX/lib/libFreeImage.a
	cp Dist/FreeImage.h $PREFIX/include/FreeImage.h
	cd ..
	touch $PKGLOCKFILE
fi

#install cmake
#hacks:
#	if you set the *FLAGS environment variables, it may fail on a test.
#	make install copies to the wrong location
PKGNAME="cmake-2.8.3"
PKGLOGDIR="$LOGDIR/$PKGNAME"
PKGLOCKFILE="$LOCKDIR/${PKGNAME}_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	printc "Installing $PKGNAME..."
	mkdir -p $PKGLOGDIR
	printc "    Downloading..."
	wget -q -c -P $DLDIR http://www.cmake.org/files/v2.8/$PKGNAME.tar.gz
	printc "    Extracting..."
	extract $DLDIR/$PKGNAME.tar.gz 2> $PKGLOGDIR/extract.log
	mkdir -p $PKGNAME/mingw_build
	cd $PKGNAME/mingw_build
	printc "    Running configure..."
	../configure --prefix=$PREFIX $CONFIGURE_EXTRA_FLAGS > $PKGLOGDIR/configure.log
	printc "    Building..."
	make $MAKEOPTS > $PKGLOGDIR/build.log
	printc "    Installing..."
	cp bin/cmake.exe $PREFIX/bin/cmake.exe
	make install > $PKGLOGDIR/install.log
	cd ../..
	touch $PKGLOCKFILE
fi

export CFLAGS="-O3 -msse2 -ffast-math -mthreads -DNDEBUG -I$PREFIX/include $CFLAGS"
#without -msse2 ogre is not building
export CXXFLAGS="-O3 -msse2 -ffast-math -mthreads -DNDEBUG -I$PREFIX/include $CXXFLAGS"

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
#hacks:
#	bjam generated in msys is not working, we need prebuilt bjam.
#	"./bjam install" is not working in msys, we need to install it manually.
PKGLOCKFILE="$LOCKDIR/boost_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	wget -c -P $DLDIR http://sourceforge.net/projects/boost/files/boost-jam/3.1.18/boost-jam-3.1.18-1-ntx86.zip/download
	extract $DLDIR/boost-jam-3.1.18-1-ntx86.zip
	wget -c -P $DLDIR http://sourceforge.net/projects/boost/files/boost/1.46.1/boost_1_46_1.tar.bz2/download
	extract $DLDIR/boost_1_46_1.tar.bz2
	ln -s $PWD/boost-jam-3.1.18-1-ntx86/bjam.exe $PWD/boost_1_46_1/bjam
	cd boost_1_46_1
	./bjam --with-thread --with-date_time --stagedir=$PREFIX --layout=system variant=release link=shared toolset=gcc
	#"./bjam install" is not working in msys, we need to install the headers manually.
	cp -r boost $PREFIX/include
	mv $PREFIX/lib/libboost_date_time.dll $PREFIX/bin/libboost_date_time.dll
	mv $PREFIX/lib/libboost_thread.dll $PREFIX/bin/libboost_thread.dll
	cd ..
	touch $PKGLOCKFILE
fi

#install lua
PKGLOCKFILE="$LOCKDIR/lua_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	wget -c -P $DLDIR http://www.lua.org/ftp/lua-5.1.4.tar.gz
	extract $DLDIR/lua-5.1.4.tar.gz
	cd lua-5.1.4
	make mingw $MAKEOPTS
	make install INSTALL_TOP=$PREFIX
	#install lua5.1.pc
	wget -c -P $DLDIR http://sajty.elementfx.com/lua5.1.pc
	cp $DLDIR/lua5.1.pc ./lua5.1.pc
	export PREFIX_ESCAPED=$(echo $PREFIX | sed -e 's/\(\/\|\\\|&\)/\\&/g')
	sed -i "s/TPL_PREFIX/$PREFIX_ESCAPED/g" ./lua5.1.pc 
	mv ./lua5.1.pc $PREFIX/lib/pkgconfig/lua5.1.pc
	cd ..
	touch $PKGLOCKFILE
fi
#install tolua++
#hacks:
#	tolua uses scons, which needs python, which is big.
PKGLOCKFILE="$LOCKDIR/tolua++_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	wget -c -P $DLDIR http://www.codenix.com/~tolua/tolua++-1.0.93.tar.bz2
	extract $DLDIR/tolua++-1.0.93.tar.bz2
	cd tolua++-1.0.93
	cp include/tolua++.h $PREFIX/include/tolua++.h
	cd src/lib
	gcc $CFLAGS -c -I$PREFIX/include -L$PREFIX/lib *.c
	ar cq libtolua++.a *.o
	cp libtolua++.a $PREFIX/lib/libtolua++.a
	cd ../bin
	gcc $CFLAGS $LDFLAGS -o tolua++ -I$PREFIX/include -L$PREFIX/lib -mwindows tolua.c toluabind.c -ltolua++ -llua
	cp tolua++.exe $PREFIX/bin/tolua++.exe
	cd ../../..
	touch $PKGLOCKFILE
fi

#install openal-soft
PKGLOCKFILE="$LOCKDIR/openal-soft_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	wget -c -P $DLDIR http://kcat.strangesoft.net/openal-releases/openal-soft-1.13.tar.bz2
	extract $DLDIR/openal-soft-1.13.tar.bz2
	cd openal-soft-1.13
	cd build
	cmake -DCMAKE_INSTALL_PREFIX=$PREFIX -G"MSYS Makefiles" ..
	make all $MAKEOPTS
	make install
	cd ../..
	touch $PKGLOCKFILE
fi

#install freealut
FILENAME="freealut-1.1.0-src.zip"
installpackage "http://connect.creativelabs.com/openal/Downloads/ALUT/$FILENAME" "$FILENAME"

#install Cg
PKGLOCKFILE="$LOCKDIR/Cg_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	cp -r "$CG_INC_PATH" $PREFIX
	cp "$CG_BIN_PATH/cg.dll" $PREFIX/bin/cg.dll
	pexports $PREFIX/bin/cg.dll | sed "s/^_//" > libCg.def
	dlltool --add-underscore -d libCg.def -l $PREFIX/lib/libCg.a
	rm libCg.def
	touch $PKGLOCKFILE
fi


#install Ogre3D
#hacks:
#	its not creating ogre.pc, we need to create them manually.
PKGLOCKFILE="$LOCKDIR/Ogre_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	wget -c -P $DLDIR http://sourceforge.net/projects/ogre/files/ogre/1.7/ogre_src_v1-7-3.tar.bz2/download
	extract $DLDIR/ogre_src_v1-7-3.tar.bz2
	cd ogre_src_v1-7-3
	mkdir -p build
	cd build
	cmake -DCMAKE_INSTALL_PREFIX=$PREFIX -G"MSYS Makefiles" \
	-DOGRE_INSTALL_DEPENDENCIES=false -DOGRE_BUILD_SAMPLES=false -DOGRE_BUILD_PLUGIN_BSP=false \
	-DOGRE_BUILD_PLUGIN_OCTREE=false -DOGRE_BUILD_PLUGIN_PCZ=false -DOGRE_BUILD_RENDERSYSTEM_D3D9=false \
	-DOGRE_BUILD_COMPONENT_RTSHADERSYSTEM=false ..
	make all $MAKEOPTS
	make install
	#copy to get it available without configuration name.
	cp -r $PREFIX/bin/RelWithDebInfo/* $PREFIX/bin
	cp -r $PREFIX/lib/RelWithDebInfo/* $PREFIX/lib

	#get *.pc files.
	wget -c -P $DLDIR http://sajty.elementfx.com/ogre_package.zip
	extract $DLDIR/ogre_package.zip
	export PREFIX_ESCAPED=$(echo $PREFIX | sed -e 's/\(\/\|\\\|&\)/\\&/g')
	find . -maxdepth 1 -name "OGRE*.pc" -exec sed -i "s/TPL_PREFIX/$PREFIX_ESCAPED/g" '{}' \;
	mv ./OGRE*.pc $PREFIX/lib/pkgconfig
	cd ../..
	touch $PKGLOCKFILE
fi

#install CEGUI
PKGLOCKFILE="$LOCKDIR/CEGUI_installed.lock"
if [ ! -f $PKGLOCKFILE ]; then
	wget -c -P $DLDIR http://sourceforge.net/projects/crayzedsgui/files/CEGUI%20Mk-2/0.7.5/CEGUI-0.7.5.tar.gz/download
	extract $DLDIR/CEGUI-0.7.5.tar.gz
	cd CEGUI-0.7.5
	./configure --prefix=$PREFIX --disable-samples --disable-opengl-renderer --disable-irrlicht-renderer --disable-xerces-c \
	--disable-libxml --disable-expat --disable-directfb-renderer \
	--enable-freeimage --enable-ogre-renderer --enable-lua-module --enable-external-toluapp \
	FreeImage_CFLAGS="-DUSE_FREEIMAGE_LIBRARY -I$PREFIX/include" FreeImage_LIBS="-lFreeImage" \
	toluapp_CFLAGS="-I$PREFIX/include" toluapp_LIBS="-ltolua++" \
	MINGW32_BUILD=true CEGUI_BUILD_LUA_MODULE_UNSAFE=true CEGUI_BUILD_TOLUAPPLIB=true \
	$CONFIGURE_EXTRA_FLAGS
	make $MAKEOPTS
	make install
	cd ..
	touch $PKGLOCKFILE
fi
