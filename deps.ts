import { Construct } from 'constructs';
import { App, Chart, Helm, Include } from 'cdk8s';
import { Namespace } from 'cdk8s-plus-27';

const kubeVersion = '1.27.3'

export class LocalPathProvisioner extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'kube-system',
      labels: {
        'prune-id': id,
      },
    });

    new Helm(this, 'chart', {
      chart: 'submodules/local-path-provisioner/deploy/chart/local-path-provisioner/',
      namespace: this.namespace,
      helmFlags: ['--kube-version', kubeVersion, '--include-crds'],
      values: {
        nodePathMap: [
          {
            node: 'DEFAULT_PATH_FOR_NON_LISTED_NODES', 
            paths: ['/var/storage/local-path-provisioner'],
          },
        ],
        storageClass: {
          reclaimPolicy: 'Retain',
        }
      },
    });
  }
}

export class TiDB extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'tidb-admin',
      labels: {
        'prune-id': id,
      },
    });

    new Namespace(this, 'namespace', {
      metadata: {
        name: this.namespace,
      },
    });

    new Helm(this, 'chart', {
      chart: 'submodules/tidb-operator/charts/tidb-operator',
      namespace: this.namespace,
      helmFlags: ['--kube-version', kubeVersion, '--include-crds'],
    });

    new Include(this, 'crds', {
      url: 'submodules/tidb-operator/manifests/crd.yaml'
    });
  }
}

export class Rook extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'rook-admin',
      labels: {
        'prune-id': id,
      }
    });

    new Namespace(this, 'namespace', {
      metadata: {
        name: this.namespace,
        labels: {
          'pod-security.kubernetes.io/enforce': 'privileged',
          'pod-security.kubernetes.io/audit': 'privileged',
          'pod-security.kubernetes.io/warn': 'privileged',
        },
      },
    });

    new Helm(this, 'operator-helm-chart', {
      chart: 'rook-release/rook-ceph',
      namespace: this.namespace,
      helmFlags: ['--kube-version', kubeVersion, '--include-crds'],
    });

  }
}

export class Traefik extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'traefik',
      labels: {
        'prune-id': id,
      }
    });

    new Namespace(this, 'namespace', {
      metadata: {
        name: this.namespace,
      },
    });

    new Helm(this, 'chart', {
      chart: 'traefik/traefik',
      namespace: this.namespace,
      values: {
        ingressRoute: {
          dashboard: {
            enabled: false,
          },
        },
        additionalArguments: ['--serversTransport.insecureSkipVerify=true'],
      },
      helmFlags: ['--kube-version', kubeVersion, '--include-crds'],
    });
  }
}

export class MetalLB extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'metallb-system',
      labels: {
        'prune-id': id,
      }
    });

    new Namespace(this, 'namespace', {
      metadata: {
        name: this.namespace,
        labels: {
          'pod-security.kubernetes.io/enforce': 'privileged',
          'pod-security.kubernetes.io/audit': 'privileged',
          'pod-security.kubernetes.io/warn': 'privileged',
        },
      },
    });

    new Helm(this, 'chart', {
      chart: 'metallb/metallb',
      namespace: this.namespace,
      helmFlags: ['--kube-version', kubeVersion, '--include-crds'],
    });
  }
}

export class ExternalSecrets extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'external-secrets',
      labels: {
        'prune-id': id,
      }
    });

    new Namespace(this, 'namespace', {
      metadata: {
        name: this.namespace,
      },
    });

    new Helm(this, 'chart', {
      chart: 'external-secrets/external-secrets',
      namespace: this.namespace,
      helmFlags: ['--include-crds'],
    });
  }
}

const app = new App();
new LocalPathProvisioner(app, 'local-path-provisioner');
new TiDB(app, 'tidb');
new Rook(app, 'rook');
new Traefik(app, 'traefik');
new MetalLB(app, 'metallb');
new ExternalSecrets(app, 'external-secrets');
app.synth();
