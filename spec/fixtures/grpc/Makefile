ALL= targetservice/targetservice.pb.go targetservice/targetservice_grpc.pb.go target

all: $(ALL)

clean:
	rm -rf $(ALL)

target: target.go
	go build -o $@

targetservice/targetservice.pb.go: proto/targetservice.proto
	protoc -I proto/ --go_out=. --go-grpc_out=. proto/targetservice.proto

targetservice/targetservice_grpc.pb.go: proto/targetservice.proto
	protoc -I proto/ --go_out=. --go-grpc_out=. proto/targetservice.proto
