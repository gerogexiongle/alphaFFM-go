.PHONY: all clean test fmt benchmark deps

# Build flags to reduce binary size
LDFLAGS=-ldflags="-s -w" -trimpath

# 下载依赖
deps:
	go mod download

all: deps
	go build $(LDFLAGS) -o bin/ffm_train cmd/ffm_train/main.go
	go build $(LDFLAGS) -o bin/ffm_predict cmd/ffm_predict/main.go

clean:
	rm -f bin/ffm_train bin/ffm_predict

test:
	go test -v ./pkg/...

fmt:
	go fmt ./...

.DEFAULT_GOAL := all

