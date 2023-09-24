import { Construct } from 'constructs';
import { Chart, Lazy } from 'cdk8s';
import { ConfigMap, Secret, StatefulSet, Volume, EnvValue, Service } from 'cdk8s-plus-27';
import * as fs from 'fs';
import { createHash } from 'crypto';

function serviceDnsName(service: Service): string {
  const namespace = service.metadata.namespace ?? Chart.of(service).namespace ?? 'default';
  return `${service.name}.${namespace}.svc.cluster.local`;
}

const DEFAULT_REDIS_IMAGE = 'redis:7.2';
const DEFAULT_REDIS_PORT = 6379;
const DEFAULT_SENTINEL_PORT = 5000;

export interface RedisProps {
  sentinel: RedisSentinelProps,
  redis: RedisRedisProps,
  image?: string,
}

export interface RedisSentinelProps {
  serviceName?: string,
  statefulSetName?: string,
  port?: number,
  replicas: number,
  masterName: string,
}

export interface RedisRedisProps {
  serviceName?: string,
  statefulSetName?: string,
  port?: number,
  replicas: number,
}

export class Redis extends Construct {
  readonly sentinelStatefulSet: StatefulSet;
  readonly sentinelService: Service;
  readonly redisStatefulSet: StatefulSet;
  readonly redisService: Service;

  public get sentinelHostname(): string {
    return serviceDnsName(this.sentinelService);
  }

  public get sentinelPort(): number {
    return this.sentinelService.ports.find(port => port.name == 'sentinel')!.port;
  }

  constructor(scope: Construct, id: string, props: RedisProps) {
    super(scope, id);

    const image = props.image ?? DEFAULT_REDIS_IMAGE;
    const redisPort = props.redis.port ?? DEFAULT_REDIS_PORT;
    const sentinelPort = props.sentinel.port ?? DEFAULT_SENTINEL_PORT;

    this.sentinelService = new Service(this, 'sentinel-service', {
      metadata: {
        ...((p) => p.name ? p : {})({name: props.sentinel.serviceName}),
      },
      clusterIP: 'None',
      ports: [{
        name: 'sentinel',
        port: sentinelPort,
        targetPort: sentinelPort,
      }],
    });

    this.redisService = new Service(this, 'redis-service', {
      metadata: {
        ...((p) => p.name ? p : {})({name: props.redis.serviceName}),
      },
      clusterIP: 'None',
      ports: [{
        name: 'redis',
        port: redisPort,
        targetPort: redisPort,
      }],
    });

    const config = new ConfigMap(this, 'config', {
      data: {
        'REDIS_NODES': Lazy.any({produce: () => [...Array(props.redis.replicas).keys()]
          .map(i =>
            `${this.redisStatefulSet.name}-${i}.${serviceDnsName(this.redisService)}`
          ).join(',')}),
        'redis.conf': fs.readFileSync('files/redis.conf').toString(),
      }
    });

    const scripts = new ConfigMap(this, 'scripts', {
      data: {
        'sentinel_init.sh': fs.readFileSync('files/sentinel_init.sh').toString(),
        'redis_init.sh': fs.readFileSync('files/redis_init.sh').toString(),
      }
    });

    const secret = Secret.fromSecretName(this, 'redis-secret', 'redis-secret');

    const sentinelConfigVolume = Volume.fromEmptyDir(this, 'sentinel-config', 'sentinel-config');
    const sentinelDataVolume = Volume.fromEmptyDir(this, 'sentinel-data', 'sentinel-data');
    const sentinelScriptsVolume = Volume.fromConfigMap(this, 'sentinel-scripts', scripts, {
      defaultMode: 0o777,
      items: {
        'sentinel_init.sh': { path: 'sentinel_init.sh' },
      }
    });

    this.sentinelStatefulSet = new StatefulSet(this, 'sentinel', {
      metadata: {
        ...((p) => p.name ? p : {})({name: props.sentinel.statefulSetName}),
      },
      podMetadata: {
        annotations: {
          'configmap.hash': createHash('sha256').update(scripts.data['sentinel_init.sh']).digest('base64'),
        },
      },
      service: this.sentinelService,
      replicas: props.sentinel.replicas,
      securityContext: {
        user: 1000,
        group: 1000,
      },
      initContainers: [{
        name: 'config',
        image,
        command: ['sh', '-c', '/scripts/sentinel_init.sh'],
        envVariables: {
          'REDIS_PASSWORD': EnvValue.fromSecretValue({secret, key: 'REDIS_PASSWORD'}),
          'REDIS_NODES': EnvValue.fromConfigMap(config, 'REDIS_NODES'),
          'SENTINEL_MASTER_NAME': EnvValue.fromValue(props.sentinel.masterName),
          'SENTINEL_SERVICE_NAME': EnvValue.fromValue(serviceDnsName(this.sentinelService)),
          'SENTINEL_PORT': EnvValue.fromValue(sentinelPort.toString()),
        },
        volumeMounts: [
          {
            path: '/etc/redis',
            volume: sentinelConfigVolume,
          },
          {
            path: '/scripts/',
            volume: sentinelScriptsVolume,
          }
        ]
      }],
      containers: [{
        name: 'sentinel',
        image,
        command: ['redis-sentinel'],
        args: ['/etc/redis/sentinel.conf'],
        ports: [{
          name: 'sentinel',
          number: sentinelPort,
        }],
        volumeMounts: [
          {
            path: '/etc/redis',
            volume: sentinelConfigVolume,
          },
          {
            path: '/data',
            volume: sentinelDataVolume,
          },
        ]
      }],
    });

    const redisConfigVolume = Volume.fromEmptyDir(this, 'redis-config', 'redis-config');
    const redisDataVolume = Volume.fromEmptyDir(this, 'redis-data', 'redis-data');
    const redisTmpConfigVolume = Volume.fromConfigMap(this, 'redis-tmp-config', config, {
      items: {
        'redis.conf': { path: 'redis.conf' },
      },
    });
    const redisScriptsVolume = Volume.fromConfigMap(this, 'redis-scripts', scripts, {
      defaultMode: 0o777,
      items: {
        'redis_init.sh': { path: 'redis_init.sh' },
      },
    });

    this.redisStatefulSet = new StatefulSet(this, 'redis', {
      metadata: {
        ...((p) => p.name ? p : {})({name: props.redis.statefulSetName}),
      },
      podMetadata: {
        annotations: {
          'configmap.hash': createHash('sha256').update(scripts.data['redis_init.sh']).update(config.data['redis.conf']).digest('base64'),
        },
      },
      service: this.redisService,
      replicas: props.redis.replicas,
      securityContext: {
        user: 1000,
        group: 1000,
      },
      initContainers: [{
        name: 'config',
        image,
        command: ['sh', '-c', '/scripts/redis_init.sh'],
        envVariables: {
          'REDIS_PASSWORD': EnvValue.fromSecretValue({secret, key: 'REDIS_PASSWORD'}),
          'SENTINEL_MASTER_NAME': EnvValue.fromValue(props.sentinel.masterName),
          'SENTINEL_SERVICE_NAME': EnvValue.fromValue(serviceDnsName(this.sentinelService)),
          'SENTINEL_PORT': EnvValue.fromValue(sentinelPort.toString()),
          'REDIS_SERVICE_NAME': EnvValue.fromValue(serviceDnsName(this.redisService)),
          'REDIS_STATEFULSET_NAME': EnvValue.fromValue(Lazy.any({produce: () => this.redisStatefulSet.name})),
          'REDIS_PORT': EnvValue.fromValue(redisPort.toString()),
        },
        volumeMounts: [
          {
            path: '/etc/redis',
            volume: redisConfigVolume,
          },
          {
            path: '/tmp/redis',
            volume: redisTmpConfigVolume,
          },
          {
            path: '/scripts',
            volume: redisScriptsVolume,
          },
        ]
      }],
      containers: [{
        name: 'redis',
        image,
        command: ['redis-server'],
        args: ['/etc/redis/redis.conf'],
        ports: [{
            number: redisPort,
            name: 'redis',
        }],
        volumeMounts: [
          {
            path: '/data',
            volume: redisDataVolume,
          },
          {
            path: '/etc/redis',
            volume: redisConfigVolume,
          },
        ],
      }],
    });
  }
}

