import { Construct } from 'constructs';
import { App, Chart, Helm } from 'cdk8s';
import { Namespace } from 'cdk8s-plus-27';

const kubeVersion = '1.27.3'

export class CloudNativePG extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id, {
      namespace: 'cnpg-system',
      labels: {
        'prune-id': id,
      }
    });

    new Namespace(this, 'namespace', {
      metadata: {
        name: this.namespace,
      },
    });

    new Helm(this, 'operator-helm-chart', {
      chart: 'cnpg/cloudnative-pg',
      namespace: this.namespace,
      helmFlags: ['--kube-version', kubeVersion, '--include-crds'],
    });

  }
}

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

const app = new App();
new CloudNativePG(app, 'cloudnative-pg');
new LocalPathProvisioner(app, 'local-path-provisioner');
app.synth();
