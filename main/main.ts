import { Construct } from 'constructs';
import { App, Chart, Helm, ApiObject, Lazy } from 'cdk8s';
import { Namespace, ServiceType, Service, Pods, /*ServiceAccount, Role, RoleBinding,*/ Secret } from 'cdk8s-plus-27';
//import { TidbCluster, TidbClusterSpecPdRequests, TidbClusterSpecTikvRequests, TidbInitializer } from './imports/pingcap.com';
import { CephCluster, CephFilesystem, CephObjectStore } from '@pythoner6/netserv-deps/imports/ceph.rook.io';
import { IpAddressPool, L2Advertisement } from '@pythoner6/netserv-deps/imports/metallb.io';
import { KubeStorageClass } from './imports/k8s';
//import { ClusterSecretStoreV1Beta1, ClusterExternalSecret, ExternalSecretV1Beta1, ClusterSecretStoreV1Beta1SpecProviderKubernetesServerCaProviderType } from '@pythoner6/netserv-deps/imports/external-secrets.io';
import { ExternalSecretV1Beta1, } from '@pythoner6/netserv-deps/imports/external-secrets.io';
import { Password } from '@pythoner6/netserv-deps/imports/generators.external-secrets.io';
import { IngressRoute, IngressRouteSpecRoutesKind, IngressRouteSpecRoutesServicesKind, IngressRouteSpecRoutesServicesPort } from '@pythoner6/netserv-deps/imports/traefik.io';
import { CrdbCluster, CrdbClusterSpecDataStorePvcSpecResourcesRequests } from '@pythoner6/netserv-deps/imports/crdb.cockroachlabs.com';
import { ClusterIssuer, Certificate } from '@pythoner6/netserv-deps/imports/cert-manager.io';
import * as process from 'process';

function namespace(obj: Construct): string {
  return (ApiObject.isApiObject(obj) ? (obj as ApiObject).metadata.namespace : undefined) 
      ?? Chart.of(obj).namespace 
      ?? 'default';
}

export interface CockroachService {
  readonly hostname: string;
  readonly sqlPort: number;
  readonly httpPort: number;
  readonly grpcPort: number;
};

export class Shared extends Chart {
  public readonly passwordGen: Password;
  public readonly cockroachService: CockroachService;
  public readonly issuer: ClusterIssuer;

  constructor(scope: Construct, id: string) {
    super(scope, id, {
      labels: {
        'prune-id': id,
      },
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

    this.issuer = new ClusterIssuer(this, 'issuer', {
      metadata: {
        namespace: 'cert-manager',
      },
      spec: {
        acme: {
          email: 'joseph@josephmartin.org',
          server: 'https://acme-v02.api.letsencrypt.org/directory',
          privateKeySecretRef: {
            name: Lazy.any({produce: () => `${this.issuer.name}-key` }),
          },
          solvers: [{
            dns01: { digitalocean: { tokenSecretRef: { name: 'digitalocean-token', key: 'access-token' } } },
          }],
        },
      },
    });

    const sqlPort = 26257;
    const grpcPort = 26258;
    const httpPort = 8080;

    const crdb = new CrdbCluster(this, 'cockroach', {
      metadata: {},
      spec: {
        cockroachDbVersion: 'v23.1.11',
        nodes: 3,
        minAvailable: 2,
        sqlPort,
        grpcPort,
        httpPort,
        affinity: {
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
        tlsEnabled: true,
        dataStore: {
          pvc: {
            spec: {
              accessModes: [ 'ReadWriteOnce' ],
              resources: { requests: { storage: CrdbClusterSpecDataStorePvcSpecResourcesRequests.fromString('50Gi') } },
              storageClassName: 'local-path',
              volumeMode: 'Filesystem',
            }
          },
        },
      },
    });

    this.cockroachService = {
      hostname: `${crdb.name}.${namespace(crdb)}.svc.cluster.local`,
      sqlPort, grpcPort, httpPort,
    };
  }
}

export interface CephProps {
  shared: Shared;
}

export class Ceph extends Chart {
  private readonly cephfsStorageClass: KubeStorageClass;
  public get cephfsStorageClassName(): string {
    return this.cephfsStorageClass.name;
  }

  constructor(scope: Construct, id: string, props: CephProps) {
    super(scope, id, {
      namespace: 'rook-admin',
      labels: {
        'prune-id': id,
      },
    });

    const dashboardPrefix = '/';
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

    new CephObjectStore(this, 's3', {
      metadata: {},
      spec: {
        metadataPool: {
          failureDomain: 'host',
          replicated: {size: 3},
        },
        dataPool: {
          failureDomain: 'host',
          replicated: {size: 3},
        },
        preservePoolsOnDelete: false,
        gateway: {
          port: 80,
          instances: 1,
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


    const cert: Certificate = new Certificate(this, 'cert', {
      metadata: {},
      spec: {
        secretName: Lazy.any({produce: () => cert.name}),
        issuerRef: {
          name: props.shared.issuer.name,
          kind: props.shared.issuer.kind,
          group: props.shared.issuer.apiGroup,
        },
        commonName: 'ceph.home.josephmartin.org',
        dnsNames: ['ceph.home.josephmartin.org'],
      },
    });

    new IngressRoute(this, 'dashboard-ingress', {
      metadata: {},
      spec: {
        entryPoints: ['websecure'],
        tls: {
          secretName: cert.name,
        },
        routes: [{
          kind: IngressRouteSpecRoutesKind.RULE,
          match: `Host(\`ceph.home.josephmartin.org\`)`,
          priority: 10,
          services: [{
            kind: IngressRouteSpecRoutesServicesKind.SERVICE,
            name: /*'rook-ceph-mgr-dashboard'*/ dashboardService.name,
            namespace: namespace(this),
            port: IngressRouteSpecRoutesServicesPort.fromNumber(dashboardPort),
            scheme: 'https',
          }],
        }],
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

    const cert: Certificate = new Certificate(this, 'cert', {
      metadata: {},
      spec: {
        secretName: Lazy.any({produce: () => cert.name}),
        issuerRef: {
          name: shared.issuer.name,
          kind: shared.issuer.kind,
          group: shared.issuer.apiGroup,
        },
        commonName: 'gitea.home.josephmartin.org',
        dnsNames: ['gitea.home.josephmartin.org'],
      },
    });

    /*
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
    */

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

    const helm = new Helm(this, 'gitea', {
      chart: process.env.npm_config_gitea!,
      namespace: this.namespace,
      helmFlags: ['--skip-tests'],
      values: {
        replicaCount: 2,
        'redis-cluster': {
          enabled: true,
          usePassword: false,
          persistence: {
            storageClass: 'local-path',
          },
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
            type: 'ClusterIP',
            clusterIP: undefined,
          },
          ssh: {
            port: 22,
            type: 'LoadBalancer',
            externalIPs: ['10.16.2.13'],
          },
        },
        image: {
          registry: "ghcr.io",
          repository: "pythoner6/gitea",
          tag: "v1.20.5",
        },
        gitea: {
          admin: {
            existingSecret: giteaAdmin.name,
          },
          additionalConfigFromEnvs: [{
            name: 'GITEA__DATABASE__PASSWD',
            //...Secret.fromSecretName(this, 'copied-secret', secret.name).envValue('GITEA__DATABASE__PASSWD'),
            ...Secret.fromSecretName(this, 'giteadbpassword', 'gitea-db-password').envValue('GITEA__DATABASE__PASSWD'),
          }],
          config: {
            server: {
              DOMAIN: 'gitea.home.josephmartin.org',
              SSH_DOMAIN: 'gitea.home.josephmartin.org',
            },
            database: {
              DB_TYPE: 'postgres',
              COCKROACH: true,
              HOST: `${props.shared.cockroachService.hostname}:${props.shared.cockroachService.sqlPort}`,
              NAME: databaseName,
              USER: databaseUser,
              SSL_MODE: 'require',
            },
            session: {
              PROVIDER: 'redis',
            },
            cache: {
              ADAPTER: 'redis',
            },
            queue: {
              TYPE: 'redis',
            },
            'cron.GIT_GC_REPOS': {
              ENABLED: false,
            },
          }
        }
      },
    });

    new IngressRoute(this, 'ingress', {
      metadata: {},
      spec: {
        entryPoints: ['websecure'],
        routes: [
          {
            kind: IngressRouteSpecRoutesKind.RULE,
            match: `Host(\`gitea.home.josephmartin.org\`)`,
            priority: 10,
            services: [{
              name: `${helm.releaseName}-http`,
              port: IngressRouteSpecRoutesServicesPort.fromNumber(8080),
            }],
          },
        ],
        tls: {
          secretName: cert.name,
        },
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
const ceph = new Ceph(app, 'ceph', {shared});
new Gitea(app, 'gitea', {
  giteaStorageClass: ceph.cephfsStorageClassName,
  shared,
});
new MetalLBConf(app, 'metallb-conf');
app.synth();
