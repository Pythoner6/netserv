#!/bin/bash
cp /tmp/redis/redis.conf /etc/redis/redis.conf
echo "requirepass ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
echo "masterauth ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
echo "replica-announce-ip ${HOSTNAME}.${REDIS_SERVICE_NAME}" >> /etc/redis/redis.conf
echo "replica-announce-port ${REDIS_PORT} " >> /etc/redis/redis.conf

DEFAULT_MASTER=${REDIS_STATEFULSET_NAME}-0

echo "finding master..."
if [ "$(timeout 5 redis-cli -h ${SENTINEL_SERVICE_NAME} -p ${SENTINEL_PORT} -a ${REDIS_PASSWORD} ping)" != "PONG" ]; then
  echo "sentinel not found, defaulting to ${DEFAULT_MASTER}"
  if [ ${HOSTNAME} == "${DEFAULT_MASTER}" ]; then
    echo "this is ${DEFAULT_MASTER}, not updating config..."
  else
    echo "updating redis.conf..."
    echo "repl-ping-replica-period 3" >> /etc/redis/redis.conf
    echo "slave-read-only no" >> /etc/redis/redis.conf
    echo "slaveof ${DEFAULT_MASTER}.${REDIS_SERVICE_NAME} ${REDIS_PORT}" >> /etc/redis/redis.conf
  fi
else
  echo "sentinel found, finding master"
  MASTER="$(redis-cli -h ${SENTINEL_SERVICE_NAME} -p 5000 -a ${REDIS_PASSWORD} sentinel get-master-addr-by-name ${SENTINEL_MASTER_NAME} | grep -E "(^${REDIS_STATEFULSET_NAME}-*)|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})")"
  if [ "${HOSTNAME}.${REDIS_SERVICE_NAME}" == ${MASTER} ]; then
    echo "this is master, not updating config..."
  else
    echo "master found : ${MASTER}, updating redis.conf"
    echo "slave-read-only no" >> /etc/redis/redis.conf
    echo "slaveof ${MASTER} ${REDIS_PORT}" >> /etc/redis/redis.conf
    echo "repl-ping-replica-period 3" >> /etc/redis/redis.conf
  fi
fi
