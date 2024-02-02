package dev.pythoner6;

import java.io.File;
//import java.lang.StringBuilder;

import io.fabric8.kubernetes.client.KubernetesClient;
import io.javaoperatorsdk.operator.api.reconciler.Context;
import io.javaoperatorsdk.operator.api.reconciler.Reconciler;
import io.javaoperatorsdk.operator.api.reconciler.UpdateControl;

import com.unboundid.util.ssl.SSLUtil;
import com.unboundid.util.ssl.PEMFileTrustManager;
import com.unboundid.util.ssl.PEMFileKeyManager;
import com.unboundid.ldap.sdk.LDAPConnectionOptions;
import com.unboundid.util.ssl.HostNameSSLSocketVerifier;
import com.unboundid.ldap.sdk.LDAPConnection;
import com.unboundid.ldap.sdk.EXTERNALBindRequest;
import com.unboundid.ldap.sdk.Filter;
import com.unboundid.ldap.sdk.SearchScope;
import com.unboundid.ldap.sdk.DN;
import com.unboundid.ldap.sdk.RDN;
import com.unboundid.ldap.sdk.SearchRequest;
//import com.unboundid.util.ByteStringBuffer;

public class LdapConfigReconciler implements Reconciler<LdapConfig> { 
  //private final KubernetesClient client;

  public LdapConfigReconciler(KubernetesClient client) {
    //this.client = client;
  }

  @Override
  public UpdateControl<LdapConfig> reconcile(LdapConfig resource, Context context) {
    try {
      System.out.println("Reconciling...");
      var trustManager = new PEMFileTrustManager(new File("certs/ca.crt"));
      var keyManager = new PEMFileKeyManager(new File("certs/tls.crt"), new File("certs/tls.key"));
      var socketFactory = new SSLUtil(keyManager, trustManager).createSSLSocketFactory();
      var options = new LDAPConnectionOptions();
      options.setSSLSocketVerifier(new HostNameSSLSocketVerifier(true));
      var address = "ldap.home.josephmartin.org";
      var port = 636;

      /*
      var chain = keyManager.getCertificateChain(null);
      if (chain == null) {
        System.out.println("Error no certificate found");
        return UpdateControl.noUpdate();
      }
      var authzid = chain[0].getSubjectX500Principal().getName();
      System.out.println("authzid: " + authzid);
      */

      System.out.println("Attempting to connect to ldap...");
      try (var connection = new LDAPConnection(socketFactory, options, address, port)) {
        System.out.println("Attempting to bind...");
        var bindResult = connection.bind(new EXTERNALBindRequest(""));
        System.out.println("Bind successful");
        System.out.println(bindResult.toString());

        /*var result =*/ connection.search(new SearchRequest(new DN(new RDN("cn", "config")), SearchScope.SUB, Filter.create("(objectClass=*)")));
        System.out.println(resource);
        /*
        var buf = new StringBuilder();
        for (var entry : result.getSearchEntries()) {
          entry.toLDIFString(buf, 78);
          buf.append('\n');
        }
        System.out.println(buf.toString());
        */
      }
    } catch(Exception e) {
      System.out.println("ERROR OCCURRED");
      e.printStackTrace();
    }


    return UpdateControl.noUpdate();
  }
}

