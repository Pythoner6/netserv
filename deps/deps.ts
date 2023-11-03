import { Construct } from 'constructs';
import { App, Chart, Helm, Include } from 'cdk8s';
import { Namespace } from 'cdk8s-plus-27';
import * as process from 'process';

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
      chart: process.env.npm_config_local_path_provisioner!,
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
      chart: process.env.npm_config_rook!,
      namespace: this.namespace,
      helmFlags: ['--kube-version', kubeVersion, '--include-crds'],
    });

  }
}

export class CertManager extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'cert-manager',
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
      chart: process.env.npm_config_certmanager!,
      namespace: this.namespace,
      helmFlags: ['--kube-version', kubeVersion, '--include-crds'],
      values: {
        installCRDs: true,
      },
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
      chart: process.env.npm_config_traefik!,
      namespace: this.namespace,
      values: {
        ingressRoute: {
          dashboard: {
            enabled: false,
          },
        },
        deployment: {
          replicas: 3,
        },
        service: {
          externalIPs: ['10.16.2.13'],
        },
        additionalArguments: [
          '--serversTransport.insecureSkipVerify=true',
        ],
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
      chart: process.env.npm_config_metallb!,
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
      chart: process.env.npm_config_external_secrets!,
      namespace: this.namespace,
      helmFlags: ['--include-crds'],
    });
  }
}

export class CockroachDb extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      //namespace: 'cockroach-operator-system',
      labels: {
        'prune-id': id,
      }
    });

    new Include(this, 'crds', {
      url: `${process.env.npm_config_cockroachdb}/crds.yaml`,
    });

    new Include(this, 'operator', {
      url: `${process.env.npm_config_cockroachdb}/operator.yaml`,
    });
  }
}

export class WeaveworksGitops extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'weaveworks-gitops',
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
      chart: process.env.npm_config_gitops!,
      namespace: this.namespace,
    });
  }
}

const app = new App();
new LocalPathProvisioner(app, 'local-path-provisioner');
new Rook(app, 'rook');
new CertManager(app, 'cert-manager');
new Traefik(app, 'traefik');
new MetalLB(app, 'metallb');
new ExternalSecrets(app, 'external-secrets');
new CockroachDb(app, 'cockroachdb');
new WeaveworksGitops(app, 'weaveworks-gitops');
app.synth();
