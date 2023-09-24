import { Construct } from 'constructs';
import { App, Chart } from 'cdk8s';
import * as pg from './imports/postgresql.cnpg.io';
import { Namespace, ConfigMap, Secret, StatefulSet, Volume, EnvValue, Service, Deployment } from 'cdk8s-plus-27';
import * as fs from 'fs';
import { createHash } from 'crypto';

export interface RedisProps {
  redisReplicas: number,
  sentinelReplicas: number,
  image?: string,
}

export class Redis extends Construct {
  constructor(scope: Construct, id: string, props: RedisProps) {
    super(scope, id);

    const image = props.image ?? 'redis:7.2';

    const config = new ConfigMap(this, 'config', {
      data: {
        'REDIS_NODES': [...Array(props.redisReplicas).keys()].map(i => `redis-${i}.redis`).join(','),
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

    const sentinelService = new Service(this, 'sentinel-service', {
      metadata: {
        name: 'sentinel',
      },
      clusterIP: 'None',
      ports: [{
        name: 'sentinel',
        port: 5000,
        targetPort: 5000,
      }],
    });

    new StatefulSet(this, 'sentinel', {
      metadata: {
        name: 'sentinel',
      },
      podMetadata: {
        annotations: {
          'configmap.hash': createHash('sha256').update(scripts.data['sentinel_init.sh']).digest('base64'),
        },
      },
      service: sentinelService,
      replicas: props.sentinelReplicas,
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
          number: 5000,
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

    const redisService = new Service(this, 'redis-service', {
      metadata: {
        name: 'redis',
      },
      clusterIP: 'None',
      ports: [{
        name: 'redis',
        port: 6379,
        targetPort: 6379,
      }],
    });

    new StatefulSet(this, 'redis', {
      metadata: {
        name: 'redis',
      },
      podMetadata: {
        annotations: {
          'configmap.hash': createHash('sha256').update(scripts.data['redis_init.sh']).update(config.data['redis.conf']).digest('base64'),
        },
      },
      service: redisService,
      replicas: props.redisReplicas,
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
            number: 6379,
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

export class Netbox extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'netbox',
    });

    new Namespace(this, 'namespace', {
      metadata: {
        name: this.namespace,
      },
    });

    const cluster = new pg.Cluster(this, 'pg', {
      spec: {
        instances: 3,
        bootstrap: {
          initdb: {
            database: 'netbox',
            owner: 'netbox',
          },
        },
        storage: {
          size: '10Gi',
          storageClass: 'local-path'
        },
      },
    });

    new Redis(this, 'redis', {
      redisReplicas: 3,
      sentinelReplicas: 3,
    });

    const config = new ConfigMap(this, 'config', {
      data: {
        'configuration.py': fs.readFileSync('files/configuration.py').toString(),
      },
    });

    const configVolume = Volume.fromConfigMap(this, 'config-volume', config, {
      items: {
        'configuration.py': { path: 'configuration.py' },
      },
    });

    const redisSecret = Secret.fromSecretName(this, 'redis-secret', 'redis-secret');
    const postgresSecret = Secret.fromSecretName(this, 'postgres-secret', `${cluster.name}-app`);
    const netboxSecret = Secret.fromSecretName(this, 'netbox-secret', 'netbox-secret');

    const netbox = new Deployment(this, 'netbox', {
      replicas: 2,
      securityContext: {
        //user: 1000,
        //group: 1000,
        ensureNonRoot: false,
      },
      podMetadata: {
        annotations: {
          'configmap.hash': createHash('sha256').update(config.data['configuration.py']).digest('base64'),
        },
      },
      containers: [{
        name: 'netbox',
        image: 'netboxcommunity/netbox:v3.6',
        securityContext: {
          ensureNonRoot: false,
        },
        envVariables: {
          'REDIS_PASSWORD': EnvValue.fromSecretValue({secret: redisSecret, key: 'REDIS_PASSWORD'}),
          'PGPASS': EnvValue.fromSecretValue({secret: postgresSecret, key: 'pgpass'}),
          'SECRET_KEY': EnvValue.fromSecretValue({secret: netboxSecret, key: 'SECRET_KEY'}),
        },
        volumeMounts: [
          {
            path: '/etc/netbox/config',
            volume: configVolume,
          },
          {
            path: '/opt/unit/',
            volume: Volume.fromEmptyDir(this, 'netbox-tmpfiles', 'netbox-tmpfiles'),
          }
        ],
        ports: [{
          name: 'http',
          number: 8080,
        }],
      }],
    });
    netbox.exposeViaService({
      name: 'netbox',
      ports: [{
          name: 'http',
          port: 8080,
          targetPort: 8080,
      }],
    });
  }
}

const app = new App();
new Netbox(app, 'netbox');
app.synth();
