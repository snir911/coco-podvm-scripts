#! /bin/bash

QCOW2=${1:-${QCOW2:-$(pwd)/rhel9.5-created-ks.qcow2}}
IMAGE_CERTIFICATE_PEM=${2:-${IMAGE_CERTIFICATE_PEM:-$(pwd)/public_key.pem}}
IMAGE_PRIVATE_KEY=${3:-${IMAGE_PRIVATE_KEY:-$(pwd)/private.key}}

[[ -f $QCOW2 && -f $IMAGE_CERTIFICATE_PEM && -f $IMAGE_PRIVATE_KEY ]] || \
    { printf "One or more required files are missing:\n\tQCOW2=$QCOW2\n\tIMAGE_CERTIFICATE_PEM=$IMAGE_CERTIFICATE_PEM\n\tIMAGE_PRIVATE_KEY=$IMAGE_PRIVATE_KEY\n "; exit 1; }

QCOW2="$(pwd)/$(basename ${QCOW2})"
[[ -f "./$(basename $QCOW2)" ]] || { echo "$(basename $QCOW2) should be in current folder"; exit 1;}

[[ -n "${ACTIVATION_KEY}" && -n "${ORG_ID}" ]] && subscription=" --build-arg ORG_ID=${ORG_ID} --build-arg ACTIVATION_KEY=${ACTIVATION_KEY} "

[[ -n "$ROOT_PASSWORD" ]] && run_extras+=" --env ROOT_PASSWORD=$ROOT_PASSWORD "

sudo podman build \
    --cap-add SYS_ADMIN --cap-add MKNOD \
    -v $QCOW2:/disk.qcow2 \
    -v $IMAGE_CERTIFICATE_PEM:/public.pem \
    -v $IMAGE_PRIVATE_KEY:/private.key \
    -v /lib/modules:/lib/modules \
    --build-arg PODVM_IMAGE_SRC=$(basename $QCOW2) \
    --device /dev/nbd0 \
    ${subscription} \
    $run_extras \
    .

