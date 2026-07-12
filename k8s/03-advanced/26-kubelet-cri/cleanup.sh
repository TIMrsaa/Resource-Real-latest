#!/usr/bin/env bash
# 모듈 26 정리
set -euo pipefail
kubectl delete deployment target --ignore-not-found
kubectl delete pod qos-g qos-b qos-be oom-me --ignore-not-found
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
# static Pod 파일을 만들었다면 노드에서 제거 필요:
echo "static-hello.yaml을 만들었다면 노드에서 삭제하세요:"
echo "  kubectl debug node/<node> -it --image=busybox -- chroot /host rm -f /etc/kubernetes/manifests/static-hello.yaml"
echo "모듈 26 정리 완료"
