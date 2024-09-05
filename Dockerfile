# Copyright 2021 Google LLC All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG MINETEST_BUILDER_IMAGE=alpine:3.19
ARG WRAPPER_BUILDER_IMAGE=golang:alpine3.19
ARG RUNTIME_IMAGE=$MINETEST_BUILDER_IMAGE

FROM $MINETEST_BUILDER_IMAGE AS minetest_builder

WORKDIR /usr/src/

ARG LUAJIT_VERSION=v2.1
ARG MINETEST_GAME_ENGINE_VERSION=5.9.0
ARG MINETEST_GAME_VERSION=5.8.0

RUN apk add --no-cache git build-base cmake curl curl-dev zlib-dev zstd-dev \
	sqlite-dev postgresql-dev hiredis-dev leveldb-dev \
	gmp-dev jsoncpp-dev ninja ca-certificates && \
	curl -o minetest-${MINETEST_GAME_ENGINE_VERSION}.tar.gz -L https://github.com/minetest/minetest/archive/refs/tags/${MINETEST_GAME_ENGINE_VERSION}.tar.gz && \
	curl -o minetest-${MINETEST_GAME_VERSION}.tar.gz -L https://github.com/minetest/minetest_game/archive/refs/tags/${MINETEST_GAME_VERSION}.tar.gz && \
	tar --strip-components=1 -xzf minetest-${MINETEST_GAME_ENGINE_VERSION}.tar.gz && \
	mkdir minetest_game && \
	tar --strip-components=1 -xzf minetest-${MINETEST_GAME_VERSION}.tar.gz -C minetest_game/ && \
	mkdir -p games/minetest_game && \
	mv minetest_game/* games/minetest_game

RUN git clone --recursive https://github.com/jupp0r/prometheus-cpp && \
				cd prometheus-cpp && \
				cmake -B build \
					-DCMAKE_INSTALL_PREFIX=/usr/local \
					-DCMAKE_BUILD_TYPE=Release \
					-DENABLE_TESTING=0 \
					-GNinja && \
				cmake --build build && \
				cmake --install build && \
		cd /usr/src/ && \
		git clone --recursive https://github.com/libspatialindex/libspatialindex && \
				cd libspatialindex && \
				cmake -B build \
					-DCMAKE_INSTALL_PREFIX=/usr/local && \
				cmake --build build && \
				cmake --install build && \
		cd /usr/src/ && \
		git clone --recursive https://luajit.org/git/luajit.git -b ${LUAJIT_VERSION} && \
				cd luajit && \
				make amalg && make install && \
		cd /usr/src/

# Create the minetest directory
RUN mkdir minetest

RUN cp -rf CMakeLists.txt README.md builtin cmake doc\
	fonts lib misc po src irr textures minetest.conf.example /usr/src/minetest

WORKDIR /usr/src/minetest
RUN cmake -B build \
				-DCMAKE_INSTALL_PREFIX=/usr/local \
				-DCMAKE_BUILD_TYPE=Release \
				-DBUILD_SERVER=TRUE \
				-DENABLE_PROMETHEUS=TRUE \
				-DBUILD_UNITTESTS=FALSE -DBUILD_BENCHMARKS=FALSE \
				-DBUILD_CLIENT=FALSE \
				-GNinja && \
		cmake --build build && \
		cmake --install build

FROM $WRAPPER_BUILDER_IMAGE AS wrapper_builder

WORKDIR /go/src/minetest

COPY main.go go.mod ./
RUN go mod download agones.dev/agones && \
    go mod tidy && \
    go build -o wrapper

FROM $RUNTIME_IMAGE AS runtime

RUN apk add --no-cache curl gmp libstdc++ libgcc libpq jsoncpp zstd-libs \
								sqlite-libs postgresql hiredis leveldb && \
	adduser -D minetest --uid 30000 -h /var/lib/minetest && \
	chown -R minetest:minetest /var/lib/minetest

WORKDIR /var/lib/minetest

RUN mkdir -p /var/lib/minetest/.minetest/games

COPY --from=minetest_builder /usr/local/share/minetest /usr/local/share/minetest
COPY --from=minetest_builder /usr/local/bin/minetestserver /usr/local/bin/minetestserver
COPY --from=minetest_builder /usr/local/share/doc/minetest/minetest.conf.example /etc/minetest/minetest.conf
COPY --from=minetest_builder /usr/src/games* /var/lib/minetest/.minetest/games
COPY --from=minetest_builder /usr/local/lib/libspatialindex* /usr/local/lib/
COPY --from=minetest_builder /usr/local/lib/libluajit* /usr/local/lib/
COPY --from=wrapper_builder /go/src/minetest/wrapper /usr/local/bin/wrapper
COPY minetest.conf /etc/minetest/minetest.conf
COPY minetestserver.sh /usr/local/bin/minetestserver.sh

RUN chown -R minetest:minetest /usr/local/bin/wrapper /usr/local/share/minetest /var/lib/minetest/.minetest \
    /usr/local/bin/minetestserver /usr/local/bin/minetestserver.sh /etc/minetest/minetest.conf \
	/usr/local/lib

USER minetest:minetest
RUN chmod +x /usr/local/bin/wrapper \
    && chmod +x /usr/local/bin/minetestserver.sh
	
# Expose ports
EXPOSE 30000/udp 30000/tcp
VOLUME /var/lib/minetest/ /etc/minetest/

ENTRYPOINT ["/usr/local/bin/wrapper", "-i", "/usr/local/bin/minetestserver.sh"]
CMD ["-args", "--gameid minetest_game --worldname world --config /etc/minetest/minetest.conf"]