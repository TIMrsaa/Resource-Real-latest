module github.com/finn/eks-study/notification-service

go 1.25

replace github.com/finn/eks-study/shared => ../shared

require (
	github.com/finn/eks-study/shared v0.0.0-00010101000000-000000000000
	github.com/segmentio/kafka-go v0.4.51
)

require (
	github.com/klauspost/compress v1.15.9 // indirect
	github.com/pierrec/lz4/v4 v4.1.15 // indirect
)
