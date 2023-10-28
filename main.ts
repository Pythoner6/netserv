import { Construct } from 'constructs';
import { App, Chart, Helm, ApiObject, Lazy } from 'cdk8s';
import { Namespace, ServiceType, Service, Pods, ServiceAccount, Role, RoleBinding, Secret } from 'cdk8s-plus-27';
import { TidbCluster, TidbClusterSpecPdRequests, TidbClusterSpecTikvRequests, TidbInitializer } from './imports/pingcap.com';
import { CephCluster, CephFilesystem } from './imports/ceph.rook.io';
import { IpAddressPool, L2Advertisement } from './imports/metallb.io';
import { KubeStorageClass } from './imports/k8s';
import { ClusterSecretStoreV1Beta1, ClusterExternalSecret, ExternalSecretV1Beta1, ClusterSecretStoreV1Beta1SpecProviderKubernetesServerCaProviderType } from './imports/external-secrets.io';
import { Password } from './imports/generators.external-secrets.io';
import { IngressRoute, IngressRouteSpecRoutesKind, IngressRouteSpecRoutesServicesKind, IngressRouteSpecRoutesServicesPort, Middleware } from './imports/traefik.io';

export interface ITidb {
  namespace: string;
  name: string;
  host: string;
  port: number;
  url: string;
}

function namespace(obj: Construct): string {
  return (ApiObject.isApiObject(obj) ? (obj as ApiObject).metadata.namespace : undefined) 
      ?? Chart.of(obj).namespace 
      ?? 'default';
}

export class Shared extends Chart {
  public readonly passwordGen: Password;
  private readonly _tidb: TidbCluster;
  public get tidb(): ITidb {
    const host = `${this._tidb.name}-tidb.${namespace(this)}.svc.cluster.local`;
    // TODO
    const port = 4000;
    return {
      namespace: namespace(this._tidb),
      name: this._tidb.name,
      host,
      port,
      url: `${host}:${port}`
    };
  }

  constructor(scope: Construct, id: string) {
    super(scope, id, {
    });

    this.passwordGen = new Password(this, 'password', {
      metadata: {
      },
      spec: {
        length: 32,
        noUpper: false,
        allowRepeat: true,
      },
    });

    this._tidb = new TidbCluster(this, 'tidb', {
      metadata: {
      },
      spec: {
        pvReclaimPolicy: 'Retain',
        timezone: 'UTC',
        enableDynamicConfiguration: true,
        discovery: {},
        helper: {
          image: 'alpine:3.18.3',
        },
        pd: {
          baseImage: 'pingcap/pd:v7.1.1',
          replicas: 3,
          maxFailoverCount: 0,
          storageClassName: 'local-path',
          requests: {
            storage: TidbClusterSpecPdRequests.fromString('10Gi'),
          },
          config: {},
        },
        tikv: {
          baseImage: 'pingcap/tikv:v7.1.1',
          replicas: 3,
          maxFailoverCount: 0,
          storageClassName: 'local-path',
          requests: {
            storage: TidbClusterSpecTikvRequests.fromString('10Gi'),
          },
          config: {},
        },
        tidb: {
          baseImage: 'pingcap/tidb:v7.1.1',
          replicas: 2,
          service: {
            type: 'ClusterIP',
          },
          config: {},
        },
      }
    });

    /*
    new TidbDashboard(this, 'tidb-dashboard', {
      metadata: {},
      spec: {
        baseImage: 'pingcap/tidb-dashboard:v7.1.1',
        clusters: [{name: tidb.name }],
        storageClassName: 'local-path',
        requests: {
          storage: TidbDashboardSpecRequests.fromString('10Gi'),
        },
      },
    });
    */
  }
}

export class Ceph extends Chart {
  private readonly cephfsStorageClass: KubeStorageClass;
  public get cephfsStorageClassName(): string {
    return this.cephfsStorageClass.name;
  }

  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'rook-admin',
      labels: {
        'prune-id': id,
      },
    });

    const dashboardPrefix = '/ceph';
    const dashboardPort = 8443;

    new CephCluster(this, 'ceph-cluster', {
      metadata: {},
      spec: {
        cephVersion: {
          image: 'quay.io/ceph/ceph:v18.2.0',
        },
        dataDirHostPath: '/var/storage/rook',
        placement: {
          all: {
            nodeAffinity: {
              requiredDuringSchedulingIgnoredDuringExecution: {
                nodeSelectorTerms: [{
                  matchExpressions: [{
                    key: 'ceph',
                    operator: 'In',
                    values: ['yes'],
                  }],
                }],
              },
            },
          },
        },
        mon: {
          count: 3,
          allowMultiplePerNode: false,
        },
        mgr: {
          count: 2,
          allowMultiplePerNode: false,
          modules: [
            {
              name: 'pg_autoscaler',
              enabled: true,
            },
            {
              name: 'rook',
              enabled: true,
            }
          ],
        },
        dashboard: {
          enabled: true,
          ssl: true,
          port: dashboardPort,
          urlPrefix: dashboardPrefix,
        },
        monitoring: {
          enabled: false,
          metricsDisabled: true,
        },
        network: {
          connections: {
            encryption: {enabled: true},
            compression: {enabled: false},
            requireMsgr2: true,
          },
        },
        storage: {
          useAllNodes: false,
          useAllDevices: false,
          nodes: ['talos-amb-yf5', 'talos-kgn-xwp', 'talos-n6u-n7u'].map(node => ({
            name: node,
            devices: [{name: '/dev/nvme0n3'}],
          })),
        },
        disruptionManagement: {
          managePodBudgets: true,
        },
      },
    });

    const cephfs = new CephFilesystem(this, 'cephfs', {
      metadata: {},
      spec: {
        metadataPool: {
          failureDomain: 'host',
          replicated: {size: 3},
        },
        dataPools: [{
          name: 'default',
          failureDomain: 'host',
          replicated: {size: 3},
        }],
        preserveFilesystemOnDelete: false,
        metadataServer: {
          activeCount: 1,
          activeStandby: true,
        },
      },
    });

    this.cephfsStorageClass = new KubeStorageClass(this, 'cephfs-storageclass', {
      metadata: {},
      reclaimPolicy: 'Retain',
      provisioner: `${this.namespace}.cephfs.csi.ceph.com`,
      parameters: {
        clusterID: this.namespace!,
        fsName: cephfs.name,
        pool: `${cephfs.name}-default`,
        kernelMountOptions: 'ms_mode=secure',
        mounter: 'kernel',
        'csi.storage.k8s.io/provisioner-secret-name': 'rook-csi-cephfs-provisioner',
        'csi.storage.k8s.io/provisioner-secret-namespace': this.namespace!,
        'csi.storage.k8s.io/controller-expand-secret-name': 'rook-csi-cephfs-provisioner',
        'csi.storage.k8s.io/controller-expand-secret-namespace': this.namespace!,
        'csi.storage.k8s.io/node-stage-secret-name': 'rook-csi-cephfs-node',
        'csi.storage.k8s.io/node-stage-secret-namespace': this.namespace!,
      },
    });

    const dashboardService = new Service(this, 'ceph-dashboard', {
      type: ServiceType.CLUSTER_IP,
      ports: [{
        name: 'http-dashboard',
        port: dashboardPort,
        targetPort: dashboardPort,
      }],
      selector: Pods.select(this, 'ceph-dashboard-targets', {
        labels: {
          app: 'rook-ceph-mgr', 
          mgr_role: 'active',
          rook_cluster: 'rook-admin',
        },
      }),
    });

    const ingressSvcs = [{
      kind: IngressRouteSpecRoutesServicesKind.SERVICE,
      name: /*'rook-ceph-mgr-dashboard'*/ dashboardService.name,
      namespace: namespace(this),
      port: IngressRouteSpecRoutesServicesPort.fromNumber(dashboardPort),
      scheme: 'https',
    }];

    const dashboardMiddleware = new Middleware(this, 'dashboard-fixpath', {
      metadata: {},
      spec: {
        redirectRegex: {
          regex: `^(.*)${dashboardPrefix}$`,
          replacement: `\${1}${dashboardPrefix}/`,
        },
      },
    });

    new IngressRoute(this, 'dashboard-ingress', {
      metadata: {},
      spec: {
        entryPoints: ['websecure'],
        routes: [
          {
            kind: IngressRouteSpecRoutesKind.RULE,
            match: `Path(\`${dashboardPrefix}\`)`,
            priority: 10,
            middlewares: [{
              name: dashboardMiddleware.name,
            }],
            services: [{name: 'noop@internal', kind: IngressRouteSpecRoutesServicesKind.TRAEFIK_SERVICE }],
          },
          {
            kind: IngressRouteSpecRoutesKind.RULE,
            match: `PathPrefix(\`${dashboardPrefix}/\`)`,
            priority: 10,
            services: ingressSvcs,
          }
        ],
      },
    });
  }
}

interface GiteaProps {
  readonly giteaStorageClass: string;
  readonly shared: Shared;
}

export class Gitea extends Chart {
  constructor(scope: Construct, id: string, props: GiteaProps) {
    super(scope, id, {
      namespace: 'gitea',
      labels: {
        'prune-id': id,
      },
    });

    new Namespace(this, 'namespace', {
      metadata: {
        name: this.namespace,
      },
    });

    const databaseName = 'gitea';
    const databaseUser = 'gitea';

    const extSecretsServiceAcc = new ServiceAccount(this, 'ext-secrets-acc');
    const extSecretsRole = new Role(this, 'ext-secrets-role', {
      metadata: {
        namespace: props.shared.tidb.namespace,
      },
    });
    extSecretsRole.allowCreate({apiGroup: 'authorization.k8s.io', resourceType: 'selfsubjectrulesreviews'})
    const extSecretsRoleBinding = new RoleBinding(this, 'ext-secrets-role-binding', {
      metadata: {
        namespace: props.shared.tidb.namespace,
      },
      role: extSecretsRole,
    });
    extSecretsRoleBinding.addSubjects(extSecretsServiceAcc);
    const store = new ClusterSecretStoreV1Beta1(this, 'store', {
      metadata: {
        namespace: props.shared.tidb.namespace,
      },
      spec: {
        provider: {
          kubernetes: {
            server: {
              caProvider: {
                type: ClusterSecretStoreV1Beta1SpecProviderKubernetesServerCaProviderType.CONFIG_MAP,
                name: 'kube-root-ca.crt',
                namespace: props.shared.tidb.namespace,
                key: 'ca.crt',
              },
            },
            auth: {
              serviceAccount: {
                name: extSecretsServiceAcc.name,
              },
            },
          },
        },
      },
    });

    const secret: ExternalSecretV1Beta1 = new ExternalSecretV1Beta1(this, 'db-password', {
      metadata: {
        namespace: props.shared.tidb.namespace,
      },
      spec: {
        refreshInterval: "0",
        target: {
          name: Lazy.any({produce: () => secret.name}),
          template: {
            engineVersion: 'v2',
            data: {
              [databaseUser]: '{{ .password }}'
            },
          },
        },
        dataFrom: [{
          sourceRef: { 
            generatorRef: {
              apiVersion: props.shared.passwordGen.apiVersion,
              kind: props.shared.passwordGen.kind,
              name: props.shared.passwordGen.name,
            }
          },
        }],
      },
    });
    extSecretsRole.allow(['get', 'list', 'watch'], {apiGroup: '', resourceType: 'secrets', resourceName: secret.name});

    new ClusterExternalSecret(this, 'db-password-copier', {
      metadata: {},
      spec: {
        externalSecretName: secret.name,
        namespaceSelector: {
          matchExpressions: [{ key: 'kubernetes.io/metadata.name', operator: 'In', values: [namespace(this)] }],
        },
        refreshTime: '1m',
        externalSecretSpec: {
          refreshInterval: '1m',
          target: {
            name: secret.name,
          },
          secretStoreRef: {
            kind: store.kind,
            name: store.name,
          },
          data: [{
            secretKey: 'GITEA__DATABASE__PASSWD',
            remoteRef: {
              key: secret.name,
              property: databaseUser,
            },
          }]
        },
      },
    });

    new TidbInitializer(this, 'gitea-db', {
      metadata: {
        namespace: props.shared.tidb.namespace,
      },
      spec: {
        image: 'ghcr.io/pythoner6/mysqlclient:v1',
        cluster: {
          namespace: props.shared.tidb.namespace,
          name: props.shared.tidb.name,
        },
        initSql: `
          CREATE DATABASE IF NOT EXISTS gitea;
          GRANT ALL PRIVILEGES ON ${databaseName}.* TO '${databaseUser}'@'%';
        `,
        passwordSecret: secret.name,
      },
    });

    const passwordGen = new Password(this, 'password', {
      metadata: {
      },
      spec: {
        length: 32,
        noUpper: false,
        allowRepeat: true,
        symbolCharacters: '-_$@!%^&*()+={}[]?/<>',
      },
    });
    const giteaAdmin: ExternalSecretV1Beta1 = new ExternalSecretV1Beta1(this, 'admin-password', {
      spec: {
        refreshInterval: "0",
        target: {
          name: Lazy.any({produce: () => giteaAdmin.name}),
          template: {
            engineVersion: 'v2',
            data: {
              username: 'gitea_admin',
              password: '{{ .password }}',
            },
          },
        },
        dataFrom: [{
          sourceRef: { 
            generatorRef: {
              apiVersion: passwordGen.apiVersion,
              kind: passwordGen.kind,
              name: passwordGen.name,
            }
          },
        }],
      },
    });

    new Helm(this, 'gitea', {
      chart: 'gitea/gitea',
      namespace: this.namespace,
      helmFlags: ['--skip-tests'],
      values: {
        'redis-cluster': {
          enabled: false,
        },
        postgresql: { enabled: false },
        'postgresql-ha': { enabled: false },
        persistence: { 
          enabled: true,
          storageClass: props.giteaStorageClass,
          accessModes: ['ReadWriteMany'],
        },
        service: {
          http: {
            port: 8080,
            type: 'LoadBalancer',
          },
        },
        gitea: {
          admin: {
            existingSecret: giteaAdmin.name,
          },
          additionalConfigFromEnvs: [{
            name: 'GITEA__DATABASE__PASSWD',
            ...Secret.fromSecretName(this, 'copied-secret', secret.name).envValue('GITEA__DATABASE__PASSWD'),
          }],
          config: {
            database: {
              DB_TYPE: 'mysql',
              HOST: props.shared.tidb.url,
              NAME: databaseName,
              USER: databaseUser,
            },
            session: {
              PROVIDER: 'memory',
            },
            cache: {
              ADAPTER: 'memory',
            },
            queue: {
              TYPE: 'level',
            },
          }
        }
      },
    });
  }
}

export class MetalLBConf extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'metallb-system',
      labels: {
        'prune-id': id,
      },
    });

    new IpAddressPool(this, 'addresses', {
      metadata: {},
      spec: {
        addresses: ['10.16.2.11-10.16.2.99']
      },
    });
    new L2Advertisement(this, 'advertisement', {
      metadata: {},
      spec: {},
    });
  }
}

const app = new App();
const shared = new Shared(app, 'shared');
const ceph = new Ceph(app, 'ceph');
new Gitea(app, 'gitea', {
  giteaStorageClass: ceph.cephfsStorageClassName,
  shared,
});
new MetalLBConf(app, 'metallb-conf');
app.synth();
