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
�      �<�V�Ȓ����(�H�@H`�N�3�������#�6֍-)�dfx�=����G�۪����a�a�ޥY�U�������Պi�So0^{��R���>���)ӣf{�����\_�|�h���Gd�۱��Y;!!��	�v�r�E���)N�?��I�M��������������:A}4���{w��E����������G�q7��O������s�[;w�q�ûݷ�'=���a��Ԭ�:xw��4+#?$#wB�둥��Я��)Yb �N?�9�&�zP&J���,�T5B�`�����<?&#��ڍI���\�@�@Q=g�93NL��a	n1i�M�\c	�+��tQ��EШ�ZY�_�aw������ԁc���z����~�������������ِ��x���㝊���E6o8q����^�k̪�^L�k{�OS&+��*Fq�`F��`�U ��+�'u�6AS�x � &�@�����b�6��R/�B7��u�1�F�4u\��Nx1H*��K��&�����q��e&� ��G��>r.�y��� }Ϩ1B��3�Mb�4��i�
��aH:���R��Y8������5R��'6���Ͱ�4S�g�((	�a�+$N��Dy�N#��I1i�H��J���,�ʁ2�bP��F�8�Z��q�a@�(H��o�6Z-��.n!p���栌r	h[����~���8��?0�5T�	�LƐEV�;��晕tkIZQ	��,�6hZi�.O``�g3iI�d��SÁ���M��2�l{����o[�槺�j2�I&�)�v���+z��K�Vr_��
GX�HiED(����crV5O������l�_�ճ*�,�����׊������j���xR���l��	X���D̬5�&7��4���τ3�J����d0��7�;�)M��@��O쳜�eGB/��}+Ц�o�i=�W:AL=o����\�}X��yge���}�@D^G�d��3�!	�!8���紹]��ܤ�0׆���\�P�@��>[IM�]J�n�W^K�3�|Ge����DͯG6�(5q��)r.)NZ�SIE�xmB�5!kf��-�)�ƽ��W�[-H�d*�'^+�-�f8*��O��̻æ}O�d���/���]¼��$c2��F�u_��_zݣ�����r��pxp��W�ɡ'�) )?D�5�w�����|6�)7Hb����9b�{~
����/�����D��y��R�D*U&ͅ+
�n���Z��0{�K#4d'F�~4G�SO�ݟm��(C��)�t��BL'���'ݞ�A+F4,���h"G�]������{�$�5h�����v+SC�H:�9u� G��ѴB�>��/[H-������q$4V�L��=6��!�$5C,S��RʠI�QX��k���t�c�3���K3ӣ�d��.�H��Uސ#���!WNĤCk�4����?� Vl��)r�Ͼ�Y1�P�	��E����M�x0�z(Sɕڜ��D	HTNw��m>���ĆTeR���	S�m��������̍C�ϰ��fnH���sS�?��G�U�(�u�ԑ� 8b�N�e�uM��W��6,��i��'��2���?��~�p��@��$H�<k<���%�t��N�l5����lf��Dn�vg(bN;�P���Y<��"UY	k�8,����|���:���YNB��̆h#vV&�n��qy�UM�ve�®�[J����p���+{�.KxKĘ
M!���'<k�|��i-;�� E_Tһra�J�Oy�`�/��j"��u���4��V�7I����������wWǂ�V+w�����|��������=��c���ao��Ԫ��?�u����}x|����^y�������sgi���C�1�d�A~��$ kCz���&�Je�F�=�рzC���%1����L���aH�Β	^E�'�;�z=�'T�4ПBۍ�x�'�S�l%��x�'N�8ÿB��e��4�{��d���ݢvD_�Y���d�Èu���4����Ly.M(��rxEn���$]�d�a�����Wh%��\�o�(�㟗tBbwJل@����7��x%"�)	���_]]5�\r�2�Kr3,/d:�ح���8Ï	��2���ʮ`��B+�h���R�8�G*��,�ҁ �e<���5J/O����d*�Vc#95�|V!XǍ���������o1.Rċ�?9����KH�e4�='��T<���ק4���]Աh�oof�������%��������}��Ǣ����J����'�3��a�(B_��.4Xk���m�
�|9���sg�q%��R� .N��K�C�"�oD�I̶�pU�!�i?%��%g0}�34���������uXkƸ>ď��G�!��� ���<�~x���Rsˀ&�p� 3�i��p^����մ ]/A���r� �G����q'��d�v�iY��<��:�n-b�� 2�j2��E�JJX����m�%Xs�(�����w�)r�сʇ�v1�����w�F�K?Z@��6����bliP�<T[e^ng��+ ;x��4AQ>z�%װd �Z��
� dg'�\&Ɇ^W� _��@:�H)��˼%�NI�d���U�T�:����6I�x����a5݀��$`,}CӣZ� �6�2�.�C��č�YL�#�7ؙ%wiY��>�)� U+b�.y��W����g�Av4CQy�;DJ��Kg����I���N�����\��F�!��^�w�����v�w{���^���c�h�'�'ۮ<ag�t�����l`!.Y� ;�H4ώ�m<�6��$���v�҇��˧8�?����Nj�FSX�]���9�g�0��<j��M�*Ԝ�ࣰӈ�B�^����l��1,�:V��;6A���}3/r/<0n)�R?03�A�Q��|hb	�D#@�ޏv,*��2��_z`�3�'��H���q��,��5��-v��M�eo�-�$\�M68����6��9��ol��l���kj��B�ڑ3&T���J���4���j��؅W����<��ٰ��U��2��i��NU�y��f5p�_����Uk�`j��J6tة����Ι_�G�2��ȕ�p�Y�/��qX�������~7i��/�������Fs�a���4w�v"����	�a�e��Au&z��s[ϛ:�8��9ZC#�������iR�qt�7{'|�RsWb���V��כ���Ha8���`N;<�UW�pB6��B����,�L�!5��Y`UVT�s�}����Q�������#��b�;<)�~�Χ3�
�1�I1��@@�SX�]��<1���+�	*��N��ڵ]*��̛G%��
�f�J�9��{�u����;{ncpg'��a[���{R�����ya��oWnt?r�w��VNXw�YH��!Cu�	�������D�)��5������4�W���5>�F�RI���CkF>3��J�Jb��Xq�N��1�4����D�'/a�b��|<��8-�;��b>3Ұ�\D���l���2��:}�i�[1RI6V���ZQ��HEƢ(X�R�z"I�+�&�2�|��Oȼ�+�'���Ci�`tߐ0 Ñ]�QI�\'�4-rdߓْjuS��LV��͉��"˫(b?+�4�S1�%��_D'c�i&�G�~�rŬ"$����$k���gY,�_��$��4�E���<J���R:�OH�y��<-`KQh"�Y��4�hfa�Cm��"+"��z��W������=(�T��آ��2���J�AL��y�g�0�l�Џ��NH]�t.�\a����{��>�
�
V|2����!S%,��8������v��]
 ����q�p��-g�F�-��s���pY�Y�4A�3a#}���30�X2&��gu ��Pd��,+}�ԘBt�6�`[L��.����E{g:YJ�K�.X�܂K�D�uj�n�9.٠Uf��X��od�	c��8��,�)�Z7�F��|N}9��{Z"�����\x	<�8��4g_��8�Y�� �S���c������q���`�F�	%Z^�Fs�,v�3閡O�<��.v<KZ��Wb�Y�( ��Ű	��]Bv���;�M@�|�N��C�<,��ީ�8U��z�2�"�:�t>=�Q/E��j[����"�br������:�\н_�-8*𺲪�rH����s�zFWYkZp�:�'ٛ\qڽ��a�Q��Ӈ��v�^[E��^��}w��@�u��_��D;���ޟ jA�: �ϭ���\T�b7�3Ƌ2L��������ĳ�<�Y�$���2�g�&�#�N9�(�RŃ����r�z��?Q���7�>_�_+é�>	�|jϙ|���Bx(����w9"G�j������,GWx/5ߊA�J�D�"@T	h�g��\����Am�c�@�s�`�@J>vAH?�)^���j#\^��i�^�Ď���/;>=c��`��|�ڮ�Vk��F�h�լ����&�m��x��ƋY_�|����F����h��R뫍 �W_��x�����M�@����/���:4���K��h��!�v�+����\��&Jx����?�Ub�N	�����ܪWs�+lu2��8��&��\�,߱��&�aaO99u�D�P�ƥ�Q���&�+i�ej��� �N�6-�h�	�8\cͬ7�Qk��/�gU��4ҋ�8�Y7�=eO@�����i�1U�� +	�5�W�4��c�?qp�UG����vǷ��� 8m���܀�A`�¶�5p��d�^�(�T�]Kn�{�:���-Z�����Ƕ�Ï�v���'4��~�)��ak�8�*��K��½)ő�?����z�z�oT��3���l5��ؕt��]mJD�m,���sˁD0��
�l��[�K���PB&S+X�J:�&`Mv��K{w�����ϻ�cA�_������ڛ��������c��?�Rr��dƔ��
��l4[E���Cv��a�:;�H�;(�C������?ƾ��Gx�҂iP1k�:?�l�!X����ܐN�k:���V씢G�;���;I���vm��j���2r�#����G�HfNa'������u��٥`h��r�y$���n��#���H������z�l��[��H��.҉�X�.�B��DŴ��`*�J[y��`8ڸ`�%�q���:u"�* ��0�����U�"�czPd�tE�*���L|g�Q�B븝!!;���}��$v�]$�/N�� $GT2�
T�xl�(�9�lS��������h�֋�^�Rn �aX��N�w�Z���`��ǻ�c���\o��?������ۧ'd��t;�'��t����Bg���lN�=�׉�8�)���������3�*��^w��ݷ�O�:K��	^���'b�����W�}��`�V�����i3v:P��
�J: ��l��{GF��L�����WP��q5!����`FX�����Z.���)� ~�� �8�o���	�M��A�0Sg0&nm�́X�z�n�Yr����nA��D���o�9�G�嬉�}�!^�C�{����:���ҷVm�	�\������N1��_����W'�~ҵ9~�=j����o�O~���������V����0����m��&�����<�G�����6[Y���\�������o{?����.��rmOs�����!�f��(�*�s:�_�a�ړ�W\�zIz8Gi�w�Vi� ��P�JS/P�55��C�-�g�1$�-"��Y �YMw��؆���vl�|�}���o{O�ݶ����)`�I%Gvڴ�ZuZ�vR�k�^�ٶ����m��D���6����l��_=�	�bwf � ~�Q�m�pN���`0��˵��~��F�ZH��r��48 �.��דk�\k�ߌ��{�q
�pq�:����W���u���eG�~o.��j�1.lN	U�Si�wrr����븘��cZ(j�B0�5�U@�r�B�hء�`��Z�*�'��א`����_��lex5B��#���ݿ��`:9b
*P5�C�H�B'.�iaQ�Ь���ND>GQ�Sv�z�I'[Ce���\�a$�<G�5���'@E���DTD�|b����迲��㏟d���������bxKV���b�����m���9J���T܇.�*X\5��Cm+���׽�/�GKX#���*��n���"!b+
X	?��1��B�?#X�ӧ��2"JA*^u�>�b���\_T���$���4����"��4+��I��^)]�� �����9$2��p͇��(U5i���'�\�*a�*U�&�*������MW^әC��_({�}�
�8L�hr:���r$���~�Ź5t����Ƌ�ho�C��Bx��l�k��ڇ�����.Y*�\C��@A��'��x#�ڋ�
�O�z�7/[<%�%�������P�Yoo���O�'l~�g���Jj��w�(Hj��~b�ɶd1��+*L�R�:�!�t�!�'g�����}�3�����m�]���9d��H�:�(�@�;�j�<�U�2U��
�*�J�+v�&7�K�=D��̻�Y+��J�=rO(��-M����QKl��1���Ҽ�`�������x۔:P�$JU�D7��C�x�>yS5�h�{�q┓)C"y�@�2Ž(Y}��MNߖN������߿|��q�o�_i�b�r7�&~C>C��Q�d�3x�;ic9���U�*���8HiJ���=�uKPi�eWy��3=�yf٨��Yڍ�d�#��O��U���r��!e�K�)땒��f֚�E�T��*�W-87)R��B]�xv�9QF�Z�j���[c6��+�DA�*�8�Ypo���`]�g[��Z�5'���n��v!��QE*���������\?U�"U�]-T{*-e��{�O"P��.��4��4e�7�F�ts	�\��J�;!� ��i f��Yݘ�ڧ�;��t��h|�	���"NN�5ު$�J�*Ƽ}Mp,e1xA���hkc%E�]�mfU�N�Ǖ\�;�V0�8?,#��܋e��ylB��c��ky-R�u��s]cϤ�D7Գ�����e�V�'J��
_��"��"�Bm�*�[��xg�%b��V�C.Z�U���)h+ϻ�J����l��M*s�H�î܈og�D�;��f�(��;r'�Ҋ�=ULNgϾ���H�\Y�n;�Xkh`A��� 
M� R}��1ʨ�5�A7"�o�N���޳��7־0�V�]Z�Ug�o釵|�~t@���bO��USn�?z�?[O�S~'h�	��/�v����wzvr��ޮ E�y�r��J�V$�8R�M�����12����】�a`L����<Mo�=0M��K�-�kr)���gI�{|t5�x�p��4��L{��A^'�X����{�m:N��Rv��V9��ˡA�R}H.�80�\V3!�Km��ˀh�u��Qw�\�Y�29r޲��S �:\$�>-n	�m'Q-�^j�t��I7Ԃh�L�����>M�]�b��y�5&�}���(���?W �3}.�ʩunt�\��z�#'t���:�X*1�	�J�Rԓf�M�Cs&�7�к�O���׷��j��r�\A.OZ�j��[���94H����]e���l��f07�T�c�5xb��Q�+f�'{;/ON��������uN�#��C��@&9����b�����i��nh��ӳ�`K;U��¡�dI[j�Z�|)�W?�oT;��M�U����{��"�S����g���?�p����W�)3���h(/��R�����h�y �>�G�sr��r�T�L6�U���m��w�*�<_8S	3,�Gd�e|Ho��ɗAX�"��.�PUM�O���^Q��hZ[3�p�kQ�����_yI�]��+��1������gq��l�X�1+��Z�y���P��T�(muJ2���m�AeR�#�"�R����j��J�%�l>�Ŏ�,j�E�&��~�^��ӄ�i��ݽ��� �aߛ��	��v�� v�ؖyV�*Ց\���Jͬ$���%l�(+uLL�JfAiW��b7{1������2*�>�� m�Ƕ�3[\ٴ�9�I��od����<]���Nf<PJg_P�qJfq}_)�iuB����[��[�QJ2�9�,P�C[�|Aˍ�`�:r�d��(�4��W��u�LAݔ����'�3�y��`��a>hI�'����}����t ��@��~�aŒд�IP0�X2^Y|�������̜�-f��
�A���TЗ0�vC���v��kL��B��Y�@�m�#	ӼŲ�U�y��K�U�.�d�b'�c��Yş۱��*ɱ�-����
(�j~wp��|+p��d-sCL�ċ��E�g��U,���7`'e��X�ln�������X�(;��Пk��]|H��L {Z������*BÖ^[T�Gp_c#Ր��Y�_Vb�ޏ%�-%�-�de.{�G�E"�*,�TVMX]�#�EPR������w����"{Ӡ�-J�2}��Nӂ�z5��0.�R�ۛ)�]����Vu
i��������V��^C?N2qZ�{i�m�v���)�}�8a�<	K!Y��b���ŭ��
)Q�0~m��%�բ�s98J��P��XJ����k�$rZY%�+�*�^�(=,�s:<�1�o��#�'/�tڦU	���ۓ.���H��s��N��E���� a6�
3ja�	��E��@��%��w�[��z��Hx �W�E�D_3���l���ʀ��v����4ߊ��d�ky7�l� S`�t����2����Z�d��;�k�S��d,W{m1��c���Ћ�\徑�~��0���C|Pk5���D�%g7��ㅹ�x�=���+�Ls����i��������>�v�[�����Ui�z�q��{�j��r]K��k�y+�{Q���Jj+� �<��9����5G�fs��^)�O�^ĿU"F�f���s	�����~�c=qP�]wI���Fb�`��E鮻q��r�~��pغΪ�Aajk�p���W�8��$U�ظ4zkn&���f���*�>d�6��K7ǆ�*7z�@���
/�J�0: nId��������L��l����`Q�x{i�37�Sܾ ��J�i`�T<�SI��Ȩ�+tO�[c-H��T��-�R��4�%|2Y^ԗB�L�U>و��ƯD)�e�):�,L[ԣ9���1�ZE�x_x2�I�1K��*��� �>-F�x�Y)��p���-��B:���M�|��MO�@7��'|����9�i3�fe�ZP���#T����,U�u?�1�0����zȸ K4��fP��W���l��w�u�� �x�lB����T�㇅&�-"k��z���X�b��ۂ��+����Ld� b��#iJ�df��-������"y$f�]/˺3��=�N�A*5T�T*��4���. V�m���q&_��TG�:�p�f�C�f��J���.ȕ��y�Ȏ�����4�� y���/ ?�!5e�W��	�+�X^W�|�|��t��Ta�a��!����zr�K���2hr�R{F�%9	5*N�����ԼUFӠ@�QsQNf��C$�~�H͞��^cd��WrK+�S
�
��Q��+����9��6��2LE�Ԡ��g�)Y4��fQ|Z����0V�ب���/��b{g��{�G/ϒ���ӡ�s�<gqEnMI8��f�ʕ)�����Cwʍz�n?���&t���2UdA��Â��]��py�A�$����D���b {C:d�Κ�hU�e���y7=A��]�\;�ώHk�����q	�Nښ'I�ſ����e�re���|���� �܂��r?F�|��e~훤�S�����
$d�9ɉ�sa�F��^!vU�������S!!
���������C�	pw�O<���;�F]K �\Ĕe�&vr�q�N��11�A4�c�dQ0ãb!�&AX-���Ɣ��;Q�a��0�7e�0��\� "EG�8HpQ3���*}͌�zLi��7���@��Մ�K��ڙ�9�D���y;g>���&��$|���T2����W�{%�B`n9(� ��_���;Kӷ*>v^0��u�i�'�7ΊE�ù�V��|kUN��ZЏU�M���Ea�w+��˲.V�>,��{�����و�~�n�u�^�.s����|�c�g?W,M��[nce��vV�vr�,�4�X�o=f���B�*_��[�DeOn�.�v���l��/�Cm!m������ؼ��O/����b��� 4����q��Z�ʾ�^p�_޽b<���I��g�P�ޫ%��$U_�4�IC����>)V9��l�Va�&1�VYK�p�Ik����z��ɝ��	 :�Ɔ~$�����������LJ��^��l76���ݢ���P�^�܂2c�t�G�e��D�w�������\�[RY�]��Yy���\Y2�E�5�:������>�b?�Ҭ������K(���dޕ������eyoJ�����K�X����?^	�\��^ɋ+wxy�v��Of4�G��Y�r�%�����X��y���CzgM���J.9���
�l���L�a�IJ����Q멢qhW/«��0��2IƤ�K�%oP�0kGo0{N�)h���zlVo�n�d�"�/��B���/0�������}`YCϺ��<���>�R
xs�X'^� f]��[��mx�z��ouM.Co���3���5�S7!����IA�w�0E�"��J~�S'��j�V8`�
+�:���� 5�����X�h���d���Kp1f��o��X��yސ����3���c��6>Š��2�O,�a�>�X횻�
�o	G�<�J�!K�Fj��)ң;=Ui�G��H*�^İ�y����Wn��^���e2Is����l�ѷxN�ы{����L��;bo�D��b�=�x�������tY~������a/�����n����?^���(6�9a�т��������_�X��]����`���Nʫ�4Ps��90abw Z��08w�]�BN����e���q��¬�ռW
*f�I��|k���,}t:v솑Gqb��� A_������R���)&�"�����2�6	ӭJ��+*�P�7Tm;7�I'r��ٷW|^ƽaL�
��
ޏ��[enM|Օל����<��I�s�kh8���d�O3��6%d5oP��m�����\�^�9����v�g��e06���������t=��`H���4����0�l�_x!9�a��
����f�J�-��-���/���d�BO��3�<���iD��w�i^m��5�T�N�W>��3���t�e�$%��L �x��.�t��X�Ӕ��ﵣŜ���O�<�[�76>4��?z��r��N���ι?ѕ#o�`^�*hIA�(W1>b����Y��\wY�8�b&~b�F�+�L�<;~y�%�i�S�x��x:��}�����$��,��]��\r���~�F飉�����I�#��O�!4{ე_k��v�����ą* �.��9r�|�۞�C�3�
���Q6���P���}�ڨ)]��=�O��J�Ɣm�k]�Flݹ�y?C7R*r!z?�Q:�G^0�?s�O���l���o��R����Ӗ�����	�+��9���Z]=�4l�[�7l���}�j[�)M���m@��^���7M�y�PĮC���e�Rґ��e�m��~���?Z�wRv�l??ݒ�k����N�����N�^���m=^_����>`�K�:ZY2�~`����i���^��z/��=
����E�b2�7ޖ;�x��h:��8���88�J��/�#���=��w���h/Bq?����菼p�h 3ՃQ�a��X#?L�H�v�	�	�@���U�x���k�����,�Ǡ��&���
�!�G �0������ஈI�L�mDףu��)T��\�X�A@��;;�:�௛�&��n~Y�`dV8ry�N���Ќ����g�肱P�� ��C�]��Խ���f�����LmE}� ��w&.��t�����A˝�AKPn���u����e�Cr,F�������.���{�Χ�p�Y]k����ݱ8##\�ա�,t�7H����s8�n��_��`)�7�/��w�N��Wб��i�-X=�mc�i�D����8"��H�D.�P���o(�,�9b�[��}CZN�������]4�(�r����vN��#�"�:Ѻ	��q4=�b� ��m<h���+�������p��Vܨ��h����|x��	�6�֣+o8d�W�kM�j�rw���{&������q���;g�G//�uߍ��8n�Z��[�%�� �$�$����ϩ◻'X�?F�W"�_ J.u���N���`���^x�z\w��s���;Rp�����On��j�v��?v�sY�h��,�L��h� ϔ\��s�C�6��+�1�B �]3�G����������P�SI�1�U�W���!��9�ԑ�a+�>�d�q��հ٢鲵�7����
�la�%�֑�����+GRj����{v��G,��M��QDF�P�#o����
��`�Ճ�&HI�$\1T�V4�~�o8��/�^|��ͨ��6��덇l��	�r��t��@F#b$�;lsSgk�������|#�6x�	3/a51��2�oO�K���Ѓ�ڌ:y���`%�/\��LB���u�#[ ��*m��)	Z���F��U��B��R�F��e!�6��>���Z-FY���'�{$)����5����9���WD_�PD<�~����_#lH ?
���>v�̭�#(� �ל�[������:}�������*̺׃F� ��b�7��������r������''�-�f+�z�`�Y4��b�w�e���3�{��+�1��+p
j㯖��D�W����ٺ���)�ιw/Q���0_ٲ�岁���g-�}u�c�l�\~�52u��Z_�l}E���tă���K._��-� ie�S��h�=V���o�N��)����qB�����t@R��� �8Ա����D�o~��I��>�9�x��2�O8�
��P]�<r�"_�S�g��"�[r�P����Lo�(b)C�s�,�pƌl����^�&]l	�{��~9�0ce#@��Q_�+y�@�0MG���T	� h�?їD��%Z4��D�Ҥtr��lӹ�9I'��ڷ`\=�hc��l{�G���ƎN��b���5K��,�2�f9���D�!�nP�7��h���P��w5��N4���Cc�;iy��_�Q���4qٹ?&�0rh�>�#�P��p�Q��u9
VS �wՅH	��������2���b��k, �^zq�ս�����D� ,ɬl�.�ŞXFIe ��`w�!_�eӤ��u�����������t]`N%��4뻁f��s�t/�*������ud2�]���~D��M���<�JNTH�VSU�D�E�܍<���M�?zeY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY���(�;�5� @ 