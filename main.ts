import { Construct } from 'constructs';
import { App, Chart } from 'cdk8s';
import * as pg from './imports/postgresql.cnpg.io';
import { Namespace, ConfigMap, Secret, Volume, EnvValue, Deployment } from 'cdk8s-plus-27';
import * as fs from 'fs';
import { createHash } from 'crypto';
import { Redis } from './redis';

export class Netbox extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'netbox',
      labels: {
        'prune-id': id,
      },
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

    const sentinelMasterName = 'netbox';

    const redis = new Redis(this, 'redis', {
      sentinel: {
        replicas: 3,
        masterName: sentinelMasterName,
      },
      redis: {
        replicas: 3,
      },
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
          'SENTINEL_MASTER_NAME': EnvValue.fromValue(sentinelMasterName),
          'SENTINEL_SERVICE_NAME': EnvValue.fromValue(redis.sentinelHostname),
          'SENTINEL_PORT': EnvValue.fromValue(redis.sentinelPort.toString()),
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
