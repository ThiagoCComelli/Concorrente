#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
cc -std=c11 tools/wrap-function.c -o tools/wrap-function \
  || echo "Compilation of wrap-function.c failed. If you are on a Mac, brace for impact"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      �=ks۶���_�0�Cɒ��'v��M��SGε��ε}8�HٜH$CRv�������tB���] $@�����y�ӉL`��`�&n�����b������Y����k���y���z�v��[����t�{X��#){�qbG�=���G/.�[T�/�$��� ��|�����������*���h�/�o��E�_{������Z�k�N���p�?z�z���gv|Qyw��f����iw���Ԯ��{px�ծ�������<�-��ɜ�7b�l�@X���Z�t�%�u��!k�ؒ�U�a�^��	Q�`~��Q0������%�M/#�� U`��=ᔙC;a��Ȩ
j��L�-�m�%d�w����إw.�V�z�ʿZa�������cFt��ow�z����:���.�G�?O�}'�4/�+jQ����2g��e�{�~Ģ��',�h�Icʤ
+�1'N�l3JvT��fE��ڎ�C�TB;� B�c{�`��:��1Nb7���~"0\E^���7M܏؆Ml�7�;:���e�}�^��J�p�ue!>!��L�ml���q�R��D��F��N�7�*r�i�6/���>� 7��k�r����`ݭ�۽�:���A�c�Wʦ�}V��'p��i	�g�I��z�Nb71��j֪����#��ju�ԋA	vu���q�5�EI�a W.H��mY�,c����''�MJ�K@��}1$���0	�:���`h��hzc�7��*[����i5Ukɳ�"��Q]DЮf*[��@6��Of�I��	�Ｅ�^��5��������o��g?��̒�$5�KQ�Cem�A�*-�k��])#��̱Ҋ�P?>I�i�<��w��j<�j�5^XTvrR��T�B5ON��9�UON�����p�)���݉��5�&w��4���ϔ�j5��A��ص�iX�,2���@�\'����"A���j
�M��~�Y� ����j� %fW�S����r�v^�(�R""�s�$��N�j��)mo�P�%�)�0�y�G�	�m�S5�I�K��-����|Ve߱V߹�HT��~�`ӎ2w��b���Iˇ~*�H��Mȳ.dMM`����u�q/D/�}��<�B��4
�
)Ђbj�"I��N���=k��箿.b�a'	g��=G4&5�>��A������?x������v}0y��Fb�
"DX�$�𰥄����Φ#h4�Q���pv�h�#?T��}�n�zb�L�h]U�D&U�����7jl�^d��p)`D�Tb���QHq�a���RuH<���ΓĐ��1�Ҷ��#-4.FnT�}9�T��]����e;��R�:0RE��R�Jf�aI�=gA>�h8b7cB�ç��u�¾2.�z�7��e�����xL��!&ib��Y���RM���N��!��Q��GԓX3ϥ���h<�/�礇ȡA���A�;�ٕ�T�\�,C9��bŇ(ű"���(��1���v�Z~<=K���N��o
e*�Қ�՝��Jĩ��.����;4���d!������o���|�fVWantX0E?L��u�٧��`����oG�*m(�u�hK����b��ʈtM�!�+�j��!Q��I��Ed�ONN�䫥�=�#�!
�`OZO6g�RrW������i3�Xn ��q�#����
P�w�Ae�/���(�q�J /a��"�'{��oP���/g9
�Z�-�#*+Wt��{X���	Ԯ�TQuQxCi�T�FɾQ��貄�T���4Ϡ<�g�%�G����c��P@�E%�+f^i��'f�e�TÎ6�a#޹�qU�����ު�S����yd;n������c��_�3s������ţ����}��~/�{G;[K�ʋ������.������ZZ�����q��/[K�
�k��X����7���:��?�+��'���C�wlRDD������=_썝����L�*=g�5!�Bm�)����G~�Azʗ�Z,�퉓=N�g(�m�`~���p�A%I-��[�G�m<�n�HZ�#��������H��\4�nȖH�����+�NU�h�`�����WXMOw�<�q��?.�1K��K��nd�N��+1�NXL�A��4�\fh%��rs$/$:�؍��q�2�Hd����o����� ~�vC�C������R(J�����5�Pz1DZ��O`�S���ؤ�U��:�"��W��>����aE�H�����Wy�U����9��=��?X~c�F�nt},����������}�ϝ<��_yu��o��=�����{�R���qR8CI�.��c��Ɏp��Z��k6a�+8T��hF������0)Ԁ��rq*���TZ��Y|� �����UmD��~̎�kNa�b��ޅ��*����4`���zX�?�_��=��a�����~��ѣGK�X���3b#�fg^/\��h�]M �6���� �/�������d�v�]��NfI8���imc\H �dh�]�:�����7$m��	Xs�(�����w�	R���ʻ�w0���뛃�VK?ZB��6��5�YTg���ws�oD
�~`y���	=ƒgTe�Z��
�`l{{�]�$C�Ơ_��D:2����e���SʓL�>�ʾ��I!���d'��fgtb��t�.I�X����j9�\m�e*v��č�i�"BpbЙ%i�_m��������F�=�WO����������5GQ��;ē��gSX3���������œ���{��Q#-k^�J��?[���L�w�}��y'�#o�;�Y��v�v_��XG�ã��?[?[V���s ��P;���'��v ��qVjyVrfaZ���$
k�nV.X�j�|N���YX)�I�h��l�-h�5�`z�`��,܄v!�q 1*�3��a\��σ����Cw���� ��c3������w��䖡*m�f=2�A2�=�X�"����G�fTX��J����<�+=�}5`���s�9�o�u:��F@
���Х��#���	&�[��1��;���F([�f虚�j�_+�'�ؕ�x��r28��T���W����M}����FWM:8�3��Zu��TȬ�v��W5TEB�Z(�����=�
�Qܨ��}=��a�G�MEd_��@�Z+u9��� �v�������x�]���������x�N�v�2��;!n���$�P��^6�=h��M��"��S��NF+5
#V��d�c�?�w_��k-\I��7D�Z��<=�#n��b^�9moV�G�#��B�v�̪�)6r�euhʎ�2a2�Z�����U�z��ہh��>�;,m���r�
��=�b*���&���h%�Ġ�R�W&�	+�������,��c��Ò�M��R%��h{"t�iZ8{far''��aS͘�{����+D�yn���lV��8J�w��V�X�)%O���;
4�'Ü!�~�H�1E:�&6�+�Me��=O���q5��K
e'�X5fS�TC^(�mb��[��Hm�5���@t"��/��tAh�$��<��8.�;7f�|jdi)3�7ǲ���0���:1Ǹ'� ���(׊4PW,#e�P�R�z*I*[�ܘ��n�'d^D���m�Bi�`lߐ0 Ö*Ұ�C.˓���94���Y�mH��.ZZ�+Z�s��L��.���!K�Ua	=�ѩb,<�Ƌ��_�\���R�2�NZ4`�S����Xio�j��	�O���%�R�'ɱ i�Oy�%�	�"Q$��&+m-�]�'l�r#�Ȏ;e�����6�o��� J�)9ZY)��-�B�;��[9e�1��s�m��C�Ǝ\�K/�P��0�N|C�';����̾�i�HT	I�3�m���>T�. ��b:e�S�|�I��aG�yNv�B.�8-������|b4ҝ�e���rI���6�Ձ�QR��WSQ:� �1��
}@�����_�[	ژ���)YJ�Kϑ�)^n��p"�>�s���lЉ.�[o����@V�06 (�ӚI���z�{�m?�ؗ�X��%r+���K��R��:o�8+YD��m,�%F��:b|j��	/h�{�?�?�쾨3 B�-!C����t�7��C�@y��m�x�p�Wb�Y� 
��b؄�fri�J�6Dqc��	��ϼ1�l�L�{�����;U�MM��1�Ť�BJ:��N��5Ƈz[�b*pC�-q|E�V�ɩn�����������hAQAԕ7 �C�8�����K�3��{ӂ� RD��7��L�h�1bjiz7��yg�Zt����O�q�	��@��*�����w���h���!6-�� �s;�_���Oq�����R$W���7 |��4f��9�����f�͒=S"�N9�(��!��;{��*�+�D��^C��b�VN�(	XDS���[����C�,�XR4���BW����r|�����8Լ4K$(����&����?�F�;�q�|0���]�/�4��:��6��u��V��UN���}Y��)M���n�Y�[g�N���Ȩ�i��z��o�����i=��������Zm��<_ǟ�ښ@��lu ��|�m�ϳ^֟����6�>{J?k��M�������\�!�V�W����LmuU�p����?aUb������N����~W�u:;��y�IAݐj����;b ��=�xFɱw*z��U.M{��yLW�����C�����mj�h�YtV��F[:�g~�v�T��i�r��r̤��͡�vu^(�F�`%�ʊ��?~l�n��������V�^�ǝ�Lҡ�fVo�[�3 ��0�l�(��R�2�~Q�ԙ���w��h�,B>��ޫ�-P�R�מ�V[�jW~'���q*jU�-�/SY���@B����>�z�ߨ�[���$c|�p�'	��v�	��v�\V�/��,R�h�3+��}�nH*�W<J���Df6V���2@Mh]4ٵ�m/m�ⓝ�㗱����}�gA�_A��Z�i����.�L����&����X����;��w�����S���N ��-�-��j��;��/�x?���)L񙛊u�41��=?ӫ(�l�M�$^�LLIh�b�����c;�&�3Hrg ���v�X�{��x�ϔz�vS� rz��e�|8X�u�b��������>�����=�cZ�G�3�������d���� $��|�_��	��ud���l���2�10�g :E�;�V/��"�~�d�oq����`��Dbi�Q̬���_����`�R�TԶ��U��6z����R&8Q[��X�t"k
 �q��>�ǁ��5}L6JG?C��<��s�>�8�oT؉����5���%-��h�PO|���m�������Me�'-E���L܊�"s�X�<�^Z�w~��凞7;w���}��kϒ���r�(t4:����\j�Nw��*A/���S�WU!w�>�>
x���:;H���^��ZM����e[#=/�߱F��o�`"%7wd�>v����q�Mr�wj��tJ�
��y~#�;<��L�	�jQ�E�z���W���ZsYM5�y�(Vv�d��(���39��#P���G�H�Iju��:͢3Q2���M�D�9��H�����=��)�D��^�7K�˄���J�me�zNa 8���z�3�^��3ޖ#�T���ׄCl�O�e5
�F��&���I5!>`��M0�Xi�!��z:4yڒg�ا,���u���9��?<�?8��{��4Ce�N|�v��N{b���K�����?���M<p��Rɣp�d��Q�z>?[�	,4��s/��FCo�VS�
wz�AcųǙ��5��pV��~�??�ӳe-Ib�7�,���ģ�;-?.i�f��"�|R�f���}ׅ_k|e�e��:��
Δ�ey2��P���]ms���l�����%�\����6Nl�㵏K��k,�w�����¿��������,O���v��\]._4U��潧��nͨE��}��(6P�1&<��£�W����<��͒�������|C��&��	�|3��?���Z�-�r�I��]�C���Շt���Ӕ��(���&f(l�`mC�	J|T��8�g�~)��-=?���t�Vړy�hN���_��s�M���4Y<dR���u�(������X��*����U;;��I�݌|o&���<s��@Л�����O�Ŵ���b5N��;�^�8��%']U���q���vMy��\���sZ��e[��o���ٚ��]4𴸷
�zd��kgT�"�~�O"�e��FN���t��ʦ�zY��B^l}��CT7�zI�o��~e��?���d�@}ZGG��DD
��q��1-3r��a���
���>��_t�X�ЯT�ṑLW4|�D�%W͞/3�r5K��=��{���䷉�P�����og��?n��>����XEu�"�6Ax^�AK��>�PMx���JW�_���Ó��<P[�E���Z��f���Z�~Tq�c���$˅��Ǹ�;�J�OU�� ��D?��"�+>�~߹/E���6%��L)�\��tߑ?�/(f�-�3�ʄx�O��$�⡞��H�?af+<�L���
�0]��(����vQ��dΘ���՜lt�<�烈���XMTVƄR_Z��_�r 9�~{���?}�wv������6��6v��<�����I�{�C�{��O�э�^�����~��h�ہ���ړ=�\������ �@ؽ5a�:���� ���{�����Erzpܲt�d�b"�6UGz^L��+���~s׳�\k�>n��.���+d� /[��݃n�C��M"����a0Q�F #%�p�w�d�!�'@	��<��|���CG��,V6l
2;�'�md�����D+���>5�8~�r1��z�މ����*�N�Eϕ��W	5��;��<tj�n<�F������'�@N&XҶ?=/HCj�^�Ü�%���b�B��FR he�i�WWi<N =;a�8c��F�vW�7�cWy����6���j��T�*��Ь��1�{��߶�aȖ�;Ǟ^2W��LtL��K3�>�G�V��JCK3i���|��\{��e��nlu�f�1��f������VWe3te�I"�q,�	�&S�ߤ�1.́�ɢ��hwĹ�ȚO/'s���S2`�I菈�ҍ����
=�)�Q�*B=�^��ߦ��2M��$����>�8!�o抡��#V�$F����ⱄ�Ѳ�'�#�N:������dH��	�c\Gyk��{��3��TF�!��퓃�����Kצ��懍Z��C�c��ئ�!9���|�uD�0�CR㤽��X I<�/�^��`����~cE�%�\w��<�n��*c���;��]ǂ�
m���[�5�<�P��2e���]xV��@g��cɏ��|>f� ��
��n��Y�:c�%�ֺ:�z�J�s������ȑՕ�B�;>J�W��_J]�ߌVl�Β�20}����r&��ܸ-�/ߕ��m=�`�-u����<fj9��/� �d�.��+��(�` TeB�B�U�dxg�瘽õ�������M�T{�}̬��8���	ƜO�ZG�PK.�9�/u������6���sr�{e�`6#~��HoDr ��n��DɂI���	�H=T"PJA�, ��U�8����3�ܸJ����2\���!tרŃ�vT�&���V��1/��S_P*�a������� �i-G��ǫ.�5��x��C�����~�#3� Lʁ��*��:��$u�����ܫ����Jv����]x�%�݅�Z�����f*�!�����qt�a��ݢ�]1�,ݻ�5�B��V�/�ȯ=k�6"�}��+J׾�(��vh��!�����|�y�����\���8Z�/lEc+�+|rup��Pu�%�7$��>��zw}]��բ�m��l�/�3k!�Ќ+O�ۣ���0�.�$��O��d�6) GX"O̩�#�t�%�����'B��kfʔ_pȐdx���<2,ê�/�<�ܰ�_�ACPW_����IK̂z�O�L	���eՠ���U��0p�������ל��j�T3Xo�ȅ��7�k�#֍o0�JI������K�ٿ�����������O�?`l�^,�*7���ݟgR'`��iLw�v�6mi�2\N�ics�ÍP����Z{F!�d���ŬűF�LY���A$ř?f0�XOc�#<6Fk�F$f�rB2P��м~�T�/ %��`�)�]ݵ�6֬^�UL��\A����j��K � /e�N�-������dˀ)�����V�y�l����u7w{'�v	��L�zG��K�+���\�*�Z&���k�K0CȒv-=��]��0!K���K���Vn*V���m[X�d
�Ʉ���D>����K��Ԥ&5�IMjR��Ԥ&5�IMjR��Ԥ&�� �&�� �  