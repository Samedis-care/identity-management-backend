FROM ruby:3.2.2-bullseye

RUN apt-get update --fix-missing \
  && apt-get install -y --no-install-recommends libvips-dev openssl libjemalloc2 libsnappy-dev curl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure SSL
COPY deploy/ssl /etc/ssl
# generate self signed cert if none was supplied
RUN bash -c '[ -f "/etc/ssl/key.pem" ] || openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/key.pem -out /etc/ssl/cert.pem -subj "/C=DE/ST=Local/L=Local/O=Local/OU=Local/CN=Local/emailAddress=ssl@localhost"'

WORKDIR /home/app/webapp

# Install bundle of gems
COPY Gemfile Gemfile.lock ./
RUN gem install bundler:$(cat Gemfile.lock | grep -A 1 "BUNDLED WITH" | grep -Po '[0-9]+\.[0-9]+\.[0-9]+')
RUN bundle install

ENV HOME /root

# Set Rails ENV variables
ENV RAILS_LOG_TO_STDOUT true
# Use jemalloc
RUN ln -s /usr/lib/*-linux-gnu/libjemalloc.so.2 /usr/lib/libjemalloc.so.2
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2

ENV MALLOC_CONF narenas:2,background_thread:true,abort_conf:true
# Glibc malloc
#ENV MALLOC_ARENA_MAX 2

# Add the Rails app
ADD . /home/app/webapp
ENV PATH "$PATH:/home/app/webapp/bin"
ENV RUBY_YJIT_ENABLE=1

# Download MaxMind GeoIP Database
RUN curl -L -f -o 'GeoLite2-City.mmdb' 'https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb'

# Generate Swagger Docs
RUN rails rswag:specs:swaggerize

CMD ["bash", "-c", "puma -b 'tcp://0.0.0.0:80' -e \"$([ ! -z \"$RAILS_ENV\" ] && echo \"$RAILS_ENV\" || echo 'production')\" -v -t 64:64 -w \"$([ ! -z \"$WORKER_COUNT\" ] && echo \"$WORKER_COUNT\" || nproc)\""]

# Expose service
EXPOSE 80

# Clean up
RUN rm -rf /tmp/* /var/tmp/*