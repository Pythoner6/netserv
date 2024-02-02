package dev.pythoner6;

import lombok.Builder;
import lombok.Value;
import lombok.Getter;
import lombok.AllArgsConstructor;
import lombok.extern.jackson.Jacksonized;
import com.fasterxml.jackson.annotation.JsonValue;
import com.fasterxml.jackson.annotation.JsonProperty;
import io.fabric8.generator.annotation.Pattern;

@Value @Builder @Jacksonized
public class LdapConfigSpec {
  @Value @Builder @Jacksonized
  public static class Syncrepl {
    @AllArgsConstructor
    public enum Type {
      @JsonProperty("refreshOnly")
      REFRESH_ONLY("refreshOnly"),
      @JsonProperty("refreshAndPersist")
      REFRESH_AND_PERSIST("refreshAndPersist");
      @Getter @JsonValue
      private String value;
    }

    Type type;
    @Pattern("([0-9]{2}:){3}[0-9]{2}")
    String interval;
  }

  Syncrepl syncrepl;
}
