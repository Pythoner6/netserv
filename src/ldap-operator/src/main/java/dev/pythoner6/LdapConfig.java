package dev.pythoner6;

import io.fabric8.kubernetes.api.model.Namespaced;
import io.fabric8.kubernetes.client.CustomResource;
import io.fabric8.kubernetes.model.annotation.Group;
import io.fabric8.kubernetes.model.annotation.Version;

@Version("v1alpha1")
@Group("pythoner6.dev")
public class LdapConfig extends CustomResource<LdapConfigSpec, LdapConfigStatus> implements Namespaced {}

