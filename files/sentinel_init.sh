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
#echo "sentinel monitor mymaster ${MASTER} 6379 2" >> /tmp/master
#$(cat /tmp/master)
echo "port 5000
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
sentinel monitor mymaster ${MASTER} 6379 2
sentinel down-after-milliseconds mymaster 1000
sentinel failover-timeout mymaster 10000
sentinel parallel-syncs mymaster 1
#sentinel sentinel-pass ${REDIS_PASSWORD}
sentinel auth-pass mymaster ${REDIS_PASSWORD}
#requirepass ${REDIS_PASSWORD}
sentinel announce-ip ${HOSTNAME}.sentinel
sentinel announce-port 5000
" > /etc/redis/sentinel.conf
cat /etc/redis/sentinel.conf
