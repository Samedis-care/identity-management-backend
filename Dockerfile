FROM --platform=$BUILDPLATFORM alpine AS preperation

# download GeoIP database< just once on multiplatform build

WORKDIR /root
RUN apk add --no-cache curl
# Download MaxMind GeoIP Database
RUN curl -L -f -o 'GeoLite2-City.mmdb' 'https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb'


FROM ruby:4.0.1-trixie

RUN apt-get update --fix-missing \
  && apt-get install -y --no-install-recommends libvips-dev openssl libsnappy-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /home/app/webapp

# Install bundle of gems
COPY Gemfile Gemfile.lock ./
RUN gem install bundler:$(cat Gemfile.lock | grep -A 1 "BUNDLED WITH" | grep -Po '[0-9]+\.[0-9]+\.[0-9]+')
RUN bundle install

ENV HOME=/root

# Set Rails ENV variables
ENV RAILS_LOG_TO_STDOUT=true
# Use jemalloc
#RUN ln -s /usr/lib/*-linux-gnu/libjemalloc.so.2 /usr/lib/libjemalloc.so.2
#ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2

#ENV MALLOC_CONF=narenas:2,background_thread:true,abort_conf:true
# Glibc malloc
#ENV MALLOC_ARENA_MAX 2

# Add the Rails app
ADD . /home/app/webapp
ENV PATH="$PATH:/home/app/webapp/bin"
ENV RUBY_YJIT_ENABLE=1

# Copy GeoIP database
COPY --from=preperation /root/GeoLite2-City.mmdb /home/app/webapp

# Generate Swagger Docs
RUN SHRINE_STORAGE=local FILES_DIRECTORY=/tmp rails rswag:specs:swaggerize

CMD puma -b 'tcp://0.0.0.0:80' -e "${RAILS_ENV-production}" -v -t 64:64 -w "${WORKER_COUNT-$(nproc)}"

# Expose service
EXPOSE 80

# Clean up
RUN rm -rf /tmp/* /var/tmp/*