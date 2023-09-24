#!/bin/bash
for i in ${REDIS_NODES//,/ }
do
    echo "finding master at $i"
    MASTER=$(redis-cli --no-auth-warning --raw -h $i -a ${REDIS_PASSWORD} info replication | awk '{print $1}' | grep master_host: | cut -d ":" -f2)
    
    if [ "${MASTER}" == "" ]; then
        echo "no master found"
        MASTER=
    else
        echo "found ${MASTER}"
        break
    fi
    
done
echo "port ${SENTINEL_PORT}
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
sentinel monitor ${SENTINEL_MASTER_NAME} ${MASTER} 6379 2
sentinel down-after-milliseconds ${SENTINEL_MASTER_NAME} 1000
sentinel failover-timeout ${SENTINEL_MASTER_NAME} 10000
sentinel parallel-syncs ${SENTINEL_MASTER_NAME} 1
#sentinel sentinel-pass ${REDIS_PASSWORD}
sentinel auth-pass ${SENTINEL_MASTER_NAME} ${REDIS_PASSWORD}
#requirepass ${REDIS_PASSWORD}
sentinel announce-ip ${HOSTNAME}.${SENTINEL_SERVICE_NAME}
sentinel announce-port ${SENTINEL_PORT}
" > /etc/redis/sentinel.conf
cat /etc/redis/sentinel.conf
