#!/bin/bash

bundle exec grpc_tools_ruby_protoc -I ./grpc/protos --ruby_out=./grpc/client/lib --grpc_out=./grpc/client/lib ./grpc/protos/events/v1/ingest.proto
bundle exec grpc_tools_ruby_protoc -I ./grpc/protos --ruby_out=./grpc/client/lib --grpc_out=./grpc/client/lib ./grpc/protos/health/v1/health.proto
bundle exec grpc_tools_ruby_protoc -I ./grpc/protos --ruby_out=./grpc/server/lib --grpc_out=./grpc/server/lib ./grpc/protos/events/v1/ingest.proto
bundle exec grpc_tools_ruby_protoc -I ./grpc/protos --ruby_out=./grpc/server/lib --grpc_out=./grpc/server/lib ./grpc/protos/health/v1/health.proto