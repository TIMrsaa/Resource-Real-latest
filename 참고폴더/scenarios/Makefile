SERVICES := order-service payment-service user-service notification-service frontend
ALL_MODULES := shared $(SERVICES)
REGION ?= ap-northeast-2

.PHONY: test build docker up down ecr-push tidy clean

test:
	@for s in $(ALL_MODULES); do \
		echo "→ test $$s"; \
		(cd $$s && go test ./...) || exit 1; \
	done

build:
	@mkdir -p bin
	@for s in $(SERVICES); do \
		echo "→ build $$s"; \
		(cd $$s && go build -o ../bin/$$s ./...) || exit 1; \
	done

docker:
	@for s in $(SERVICES); do \
		echo "→ docker build $$s"; \
		docker build -t eks-study/$$s:latest -f $$s/Dockerfile . || exit 1; \
	done

up:
	docker compose up -d --build

down:
	docker compose down -v

ecr-push:
	bash ../00-prerequisites/scripts/ecr-push-all.sh

tidy:
	@for s in $(ALL_MODULES); do \
		echo "→ tidy $$s"; \
		(cd $$s && go mod tidy); \
	done

clean:
	rm -rf bin/
