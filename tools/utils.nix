{pkgs}: let
  mod = pkgs.lib.trivial.mod;
in rec {
  hex = let
    hexTable = {"0"=0; "1"=1; "2"=2; "3"=3; "4"=4; "5"=5;"6"=6; "7"=7; "8"=8; "9"=9; a=10; A=10; b=11; B=11; c=12; C=12; d=13; D=13; e=14; E=14; f=15; F=15;};
    stringToCharPairs = s: builtins.genList (i: builtins.substring (i*2) 2 s) ((builtins.stringLength s) / 2);
    hexPairsToBytes = pairs: map (i: 16*hexTable.${builtins.substring 0 1 i} + hexTable.${builtins.substring 1 1 i}) pairs;
  in {
    decode = s: hexPairsToBytes (stringToCharPairs s);
  };
  base64 = let
    base64Table = [
      "A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L" "M"
      "N" "O" "P" "Q" "R" "S" "T" "U" "V" "W" "X" "Y" "Z"
      "a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m"
      "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z"
      "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "+" "/"
    ];
    encodeChunk = chunk: (
      (builtins.elemAt base64Table (mod (chunk / (64*64*64)) 64))
      + (builtins.elemAt base64Table (mod (chunk / (64*64)) 64))
      + (builtins.elemAt base64Table (mod (chunk / 64) 64))
      + (builtins.elemAt base64Table (mod chunk 64))
    );
  in {
    encode = bytes: let
      len = builtins.length bytes;
      padded = builtins.elemAt [
        bytes
        (bytes ++ [0 0])
        (bytes ++ [0])
      ] (mod len 3);
      numChunks = (builtins.length padded) / 3;
      chunks = builtins.genList (i: 256*256*(builtins.elemAt padded (i*3)) + 256*(builtins.elemAt padded (i*3+1)) + (builtins.elemAt padded (i*3+2))) numChunks;
      encodedChunks = map encodeChunk chunks;
      encoded = pkgs.lib.strings.concatStrings encodedChunks;
      encodedLen = builtins.stringLength encoded;
    in builtins.elemAt [
      encoded
      ((builtins.substring 0 (encodedLen - 2) encoded) + "==")
      ((builtins.substring 0 (encodedLen - 1) encoded) + "=")
    ] (mod len 3);
  };

  hexToBase64 = string: base64.encode (hex.decode string);
  fetchurlHexDigest = {digest, digestType ? "sha256", ...} @ args: pkgs.fetchurl (
    (removeAttrs args ["digest" "digestType"]) // {
      hash = "${digestType}-${hexToBase64 digest}";
    }
  );
}
