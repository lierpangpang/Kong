#!/usr/bin/env bash
# set -e

#---------
# Download
#---------

DEPS_HASH=$(cat .ci/setup_env.sh .travis.yml | md5sum | awk '{ print $1 }')
BUILD_TOOLS_DOWNLOAD=$DOWNLOAD_ROOT/openresty-build-tools

mkdir -p $BUILD_TOOLS_DOWNLOAD

wget -O $BUILD_TOOLS_DOWNLOAD/kong-ngx-build https://raw.githubusercontent.com/Kong/openresty-build-tools/master/kong-ngx-build
chmod +x $BUILD_TOOLS_DOWNLOAD/kong-ngx-build

export PATH=$BUILD_TOOLS_DOWNLOAD:$PATH

KONG_NGINX_MODULE_DOWNLOAD=$DOWNLOAD_CACHE/lua-kong-nginx-module-$KONG_NGINX_MODULE
if [ ! "$(ls -A $KONG_NGINX_MODULE_DOWNLOAD)" ]; then
    git clone -q -b $KONG_NGINX_MODULE https://$GITHUB_TOKEN@github.com/Kong/lua-kong-nginx-module.git $KONG_NGINX_MODULE_DOWNLOAD
fi

#--------
# Install
#--------
INSTALL_ROOT=$INSTALL_CACHE/$DEPS_HASH

kong-ngx-build -p $INSTALL_ROOT --work $DOWNLOAD_ROOT --openresty $OPENRESTY --openssl $OPENSSL --luarocks $LUAROCKS -j $JOBS --add-module $KONG_NGINX_MODULE_DOWNLOAD

OPENSSL_INSTALL=$INSTALL_ROOT/openssl
OPENRESTY_INSTALL=$INSTALL_ROOT/openresty
LUAROCKS_INSTALL=$INSTALL_ROOT/luarocks

export OPENSSL_DIR=$OPENSSL_INSTALL # for LuaSec install

export PATH=$OPENSSL_INSTALL/bin:$OPENRESTY_INSTALL/nginx/sbin:$OPENRESTY_INSTALL/bin:$LUAROCKS_INSTALL/bin:$PATH
export LD_LIBRARY_PATH=$OPENSSL_INSTALL/lib:$LD_LIBRARY_PATH # for openssl's CLI invoked in the test suite


make -C $KONG_NGINX_MODULE_DOWNLOAD LUA_LIB_DIR=${OPENRESTY_INSTALL}/lualib install

eval `luarocks path`

# -------------------------------------
# Install ccm & setup Cassandra cluster
# -------------------------------------
if [[ "$KONG_TEST_DATABASE" == "cassandra" ]]; then
  echo "Setting up Cassandra"
  docker run -d --name=cassandra --rm -p 7199:7199 -p 7000:7000 -p 9160:9160 -p 9042:9042 cassandra:$CASSANDRA
  grep -q 'Created default superuser role' <(docker logs -f cassandra)
fi

# -------------------
# Install Test::Nginx
# -------------------
if [[ "$TEST_SUITE" == "pdk" ]]; then
  CPAN_DOWNLOAD=$DOWNLOAD_ROOT/cpanm
  mkdir -p $CPAN_DOWNLOAD
  wget -O $CPAN_DOWNLOAD/cpanm https://cpanmin.us
  chmod +x $CPAN_DOWNLOAD/cpanm
  export PATH=$CPAN_DOWNLOAD:$PATH

  echo "Installing CPAN dependencies..."
  cpanm --notest Test::Nginx &> build.log || (cat build.log && exit 1)
  cpanm --notest --local-lib=$TRAVIS_BUILD_DIR/perl5 local::lib && eval $(perl -I $TRAVIS_BUILD_DIR/perl5/lib/perl5/ -Mlocal::lib)
fi

nginx -V
resty -V
luarocks --version
openssl version


set +e
