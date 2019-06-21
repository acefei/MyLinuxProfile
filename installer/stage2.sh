#!/bin/bash

setup=$(mktemp -dt "$(basename "$0").XXXXXXXXXX")
teardown(){
    rm -rf "$setup"
}
trap teardown EXIT

current_dir=$(cd `dirname ${BASH_SOURCE[0]}`; pwd)
source $current_dir/precondition.sh

essential() {
    install['yum']="epel-release gcc automake autoconf libtool make tig"
    install['apt']="build-essential"
    install_pack ${install["$distro"]}
    echo "===> essential is installed successfully."
}

for_wsl() {
    # docker run -it -v /c/Users/acefei/:/data xxx
    test -d /mnt/c || return
    $gosu mkdir /c && $gosu mount --bind /mnt/c /c

    tee -a $bashrc <<TEE
# Configure WSL to Connect to the remote docker daemon running in Docker for Windows
export DOCKER_HOST=tcp://0.0.0.0:2375 
TEE
}

make_python3() {
    remove_pack python3
    ver=3.7.2
    PY3_PREFIX=`pyenv prefix $ver`
    if [ ! -d "$PY3_PREFIX" ];then
        # install dependency
        install['yum']="ncurses-devel zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel xz xz-devel libffi-devel"
        install['apt']="make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev python-openssl"
        install_pack ${install["$distro"]}
        pyenv install $ver
        pyenv local $ver
        pyenv versions
    fi 
    export PY3_CONFIG=`$PY3_PREFIX/bin/python-config --configdir`
    echo "===> python $ver is installed successfully."
}

make_vim8() {
    test -e $local_bin/vim && return
    make_python3

    # re-build vim8 with huge feature
    install['yum']="ncurses-devel perl-devel perl-ExtUtils-Embed ruby-devel lua-devel"
    install['apt']="libncurses5-dev libperl-dev ruby-dev lua5.1 liblua5.1-dev luajit libluajit-5.1"
    install_pack ${install["$distro"]}
    echo "===> vim depandencies are installed successfully."
    
    cd $setup
    get_from_github vim
    cd vim
    #  run `make distclean' and/or `rm config.cache' and start over
    make distclean \
    && ./configure --enable-multibyte     \
                --with-features=huge      \
                --enable-rubyinterp       \
                --enable-perlinterp       \
                --enable-luainterp        \
                --enable-python3interp    \
                --with-python3-config-dir=$PY3_CONFIG  \
                --enable-fail-if-missing  \
                --prefix=$local_dir       \
    && make -j$CPU \
    && make install DESTDIR=$local_dir

    if ! grep "alias vi=$local_bin/vim" $profile > /dev/null 2>&1; then 
        echo "alias vi=$local_bin/vim" >> $profile
    fi
    git config core.editor "$local_bin/vim"
    echo "===> $local_bin/vim is installed successfully."
}

docker_utils() {
    # refer to https://get.daocloud.io
    if [ ! -x "$(command -v docker)" ]; then
        curl -sSL https://get.daocloud.io/docker | $gosu sh
        $gosu usermod -aG docker $USER

        # configure docker service
        docker_service_file=/usr/lib/systemd/system/docker.service
        if [ -e $docker_service_file ];then
            $gosu sed -i 's!^\(ExecStart=\).*!\1/usr/bin/dockerd -H tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock!' $docker_service_file
        fi
    fi

    if [ ! -e $local_bin/docker-compose ]; then
        curl -sL https://get.daocloud.io/docker/compose/releases/download/1.20.1/docker-compose-`uname -s`-`uname -m` > $local_bin/docker-compose
        chmod +x $local_bin/docker-compose
    fi
}

make_tmux(){
    test -e $local_bin/tmux && return

    install['yum']="xsel xclip"
    install['apt']="xsel xclip"
    install_pack ${install["$distro"]}

    cd $setup
    # download source files for tmux, libevent and ncurses
    get_from_github tmux
    get_from_github libevent
    curl -L ftp://ftp.gnu.org/gnu/ncurses/ncurses-6.0.tar.gz -o ncurses.tar.gz
    tar xvzf ncurses.tar.gz

    # libevent
    cd $setup/libevent*
    ./autogen.sh
    ./configure --prefix=${local_dir} --disable-shared
    make -j$CPUS
    make install

    # ncurses
    cd $setup/ncurses-*
    export CPPFLAGS="-P" # otherwise ncurse fails to build on gcc 5.x (https://gcc.gnu.org/bugzilla/show_bug.cgi?id=61832)
    ./configure --prefix=${local_dir} --without-debug --without-shared --without-normal --without-ada
    make -j$CPUS
    make install

    # tmux
    cd $setup/tmux*
    ./autogen.sh
    ./configure CFLAGS="-I$local_dir/include -I$local_dir/include/ncurses" LDFLAGS="-L$local_dir/lib -L$local_dir/include/ncurses -L$local_dir/include"
    CPPFLAGS="-I$local_dir/include -I$local_dir/include/ncurses" LDFLAGS="-static -L$local_dir/include -L$local_dir/include/ncurses -L$local_dir/lib"
    make -j$CPUS
    cp tmux $local_dir/bin

    # tmux plugins
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

    # add tmux config
    ln -sf $config/tmux.conf $tmuxconfig 
    echo ">>>>>  Add tmux config successfully..."

    echo "===> tmux is installed successfully."
}

main() {
    # select what you want to install
    essential
    for_wsl
    make_vim8
    make_tmux
    docker_utils
}

main
