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
�J: ��l��{GF��L�����WP��q5!����`FX�����Z.���)� ~�� �8�o���	�M��A�0Sg0&nm�́X�z�n�Yr����nA��D���o�9�G�嬉�}�!^�C�{����:���ҷVm�	�\������N1��_����W'�~ҵ9~�=j����o�O~���������V����0����m��&�����<�G�����6[Y���\�������o{?����.��rmOs�����!�f��(�*�s:�_�a�ړ�W\�zIz8Gi�w�Vi� ��P�JS/P�55��C�-�g�1$�-"��Y �YMw��؆���vl�|�}���o{��ݶq�g�W�h�!e>$9vZ�r�H��{%K��&m��@$$!&  �Ď~L>����S���cwf�ʌ�pO��bvvvvvfwf6�X����
n���P��I�i.���߅���$֚~�7a4pϢ8��'�C�v[��
�͢N�����-��\NS�"��攀P5�PJ���������n�b�i��Ux����W=�sE�e��^�+jY�$��NQC��Z��~�O�����?$�=�+"�rtr�T�j<f�ŉ2D�N\�+��%MC�Z!�j&8	�9J��3� Գ�Iu�T�����FB��qT[�GN�8**U�&�"�g�����D�U��O�>������'��Xe��χ���m���9*���T��.�*X\5�Cm+���׃�/��KX#���*��~���.bk
X?���O�7��	���).D��ÇB��W}��!_~Ҥ��f�VjiE*���4��~xaX���J�$J_/N���� ��A��t����q�����B�l�q'��JرZ�ɢ����."Uu���j:3�{�e����X�ǃ	2MN'��.�@0�k��AZX1A�Nhn���֋1�L,��Nw���Y{0���{ܧ��>����Wо�6Fc-ވ��ҬB�c�,���b��d���3�::��J|"���-c�,�w�D��я����r_I��N|�DYm�0�Ϭ4�v�ZLr~I���RjPg4�>2$��tg������D�z��Ŗ�X��rIv$�i���=F�^�jb)U,��B�Z���ݹɍc�t�	u`f]�h��oIb�����nK�q�xa���l��1���Ҭ�h�����Md����2�R� ����hL�hG��OQ�T�b��<�q�ɔ#��<܏����^��>��&�oKgfz�ӿ�߿x�i�o���Ŵ�n,L��x�~KQ�d�3x�;���Vdlճ
c)1A�R��wOu��TZM�U�)�=�yf٨����FF2�#U�zz`V��˙��xTuNbS�+%��ͬ5��S�"��_��̤���v�����D5xj��?[o��<K�%��9���gν��'�9tE�m��jI ֌<jB�m�ڥL�&5����|�R�~�v����P�C�Z��TX2��`�$�f�]0�i��i.,��o�B�!�$dr�+���Y��M1;�'���d�>��l���F��NƆ�pv
��V-�W�U�0f�k�c%�i�K:���d�x[�+!��m�0��vf?.Z�ٶ�)��aU٩{q�̾�"�M�]�����)�z+�\��3i��,�n��~U�u�J@���l�L/�	�T���j`���R�F�� ���P��mU.�l
��ʳ�F���R���E��)[Cp��Ae���ȥ���L�(b�W�r��;�WVD�i��t���뽗�U˕4��Ê��Ĩ����&
 ��w���BG�f���G�p��Dm��>�zc���`��/B������-���B���/���^n��}�[����3~�C����uf������잜�mw����<L9�|%p+��Q)�I���~/D�r��c*k���o~fOӛ��"LS����bD�LJ).�yR�}�=7��6�l7�޺p��I#6xu����.o��]y��]b�U��j�rh���*�`��#�4LH���uRD]6n��m&�,H�9k���)�n.��d����嶓��e/}������	jN4Ϧ���`g�N��d��y�5��}���(f��?� �3}&�ʩuat�X��z�#�u���:�X(1�	=��K�@�96�͙��B��?a�7[�
_�-瀋-s�"@,i�����
`��ΡA�S��W�hA�v�ks�L�>�Z�'Ɖmx�l�xw�����_w�����.�x�1zȱ��dg�c?���7�htt6M��6�<9����S��(�N�R�hԒ�K���~�z��n��z�����H���O�F�&>�k#L�a0a
��?��B[d�1x��R:^jI�����hz)r�>�G{�B��ːSY8O0ќV��÷A���mZ(O�|]�L��09����!ɼYЇ�Xa5��ǺBU5�>����<�QY[3s�0�kQ���<^zY�]��k��q��G������l�X�1+��Zy���P��T� ��&M2Ř�-��2��Q�<�KR������n��J�%�l>�Ŏ��kE�f���~�^�^�i�شK���^L�x�	ǰ�m�ٌ�N��t��Yl�"+Z��H.�OQ�f��N���M)+tLL�JfA�T��n0�| ȃ1M�KI�`���SY����Җyl�9����m��S�$�x�F�P��g�Z��v2���J:���*������J:��	�vGoJ݊�$����S�@��2������#G������Q���qx[���m��(?~b1��q�Q${J�f�����1b��=�=ϑ?��������+���mF���Œ��bc�^����\f�,l�0;����E�8����	�[<����g^c�������m�I��M�7�ث�ϥw/E�v�&�;��;�g�n�Ξ������fP�:�4����iV���x�[���Q����+�6�9�Xn��߀��σ>{`����z���A+��Qv�P�?�A���:��2�E<h�jX��-[x-lQ�}�5�!���y^�b���-��-fde.{�G�E<�*,�TVMX]�#�yPR�ͿOJ���̄{��iP��%b��UU'�iA�z5��0.d�����.!+�l�ZBZibj���{�Y|��ҏ�L���^m[�ݮ'y���',�'a%$kyX�0����W!e
Ư�޹l��^�r!']�����d����~�TDN+��q�T��+��%}�ãS즹"������N۴� �}{�e��r}�"]۩!��d^<	��u�Q�DH��-�9�/��*�Z���[L}���^���%"�}�y_(K����y&b+۵&PZ�|+�Z���Գ�wL�1үˠ��ӷ����w�d�9��Y���|��h񏼱�z��}+��>`֫�����jg��+�n���ss'��-yfoWΙf6�˭��-c�;3l5�!|�Ʒ,W��Z�����Qj�i,L��W��u-Ň�E���E���[(i[���)�y>���927�4 ��2z���e�['bdf�Q�~��L��x�5_�[k艃j�b>�����w��G���ƙ������a�:�����.��<T� q���T)c��譙y�B��X�0S��T)��!�1��E���7���S�n(�H}���S�����@&�~bx��zaM��;�~L��
��0����K�ؽrc<���@��\j�Lۊ����쎌�L�D��xg�Y6����/9QLe-q�����ʦ�W�d���4v%J�,{�Hљg�lQ����c.|���(��I�1+��:ٳ��1-F�x�Y)��p��-��F:��ٍ����MO�@o�{�O�(�'7K3��f
��5�r�;T�G��ܮT�u?�TP\AA=$�
�C��2�R�^�ｖc�κ�=E��7�f��7���v���İEDM�P�$X�u,v��-�{��B(�?�Lfq"v:��BN榮؂�(N��(�G|�����;�ޣ��}�#pA��
��J_��@V�dn�J;�-VN����6�ѿ�N�l}�"�{_	w�n�sr�-qޢdGk�`�`*'/Hx�3��XHM��UC����:�׵7�h>N9s�u'G�la�-ᦣ�����η�-iϨ�� �F�I ���1}�aAY�_C��Qg4
Tm`�!*�LQs������3��k�L��Zni�p*��ac<�w�v%��v5�Q���y��S�35��$���̋O�pX]��j���U\�9R�d�t�`w���i6��>����9!�Y\�[%	gc��L>u�R���Q�9t�ܘ����֋����`BN��X�8+SMT |<,h��EpZ�A�/EJ�\w�4\�b@#�7��,��f Zݹb��#�jޕ'���`�kǚ���im��>{>.�Ԓ���p��Z��I��p^�p,WF�H�[�7��~���-��~!�c����X�оI�+��* ��*GB�\���D8��hTK�%bWw{��+-|��
	Q�hg��N�>
SϏQ&`��Ϳ�Vk�褿u-�lbS��w��)��!99d��,�Q�>�E�s!6��z�l��8�	Jرs�t	�-���S�{S2����U R4��(�Eʹ'64��57f��e4�C6��e�_D<��E\<�����i'"����qל�j�H�W��M���iK1�xչW1,�-����+�b�������]����kǹ9D��)�bQ�p��m3��@����cU{��mQھŝ���{����u����^f�G$�s6��_��}-�+�e΃S�S��,��犥�|~�m�<x�Ί�N�ރ�f+@���<�^(U��ux������!�eѮ�}�����jsi����յu���O?[_��w�z��>h䃃�������}c�����{�X����j/_YR@��W4�Sa&��
M�LZj���I��	�/d��
Wj�|���
S���Al |��W��٫� ��+d�'�� �\AO�Li�h�T�}3Hp���Ɔ��_v�p�5�YP&��a�h�����=�����Jc&�-�,����Ю=� �U�,9����^s�Zp�XYq��biV��`�G��K(���dѕ������E�hJ��?��+�X����?^	�X�^ɋ+w|q�v��O�h|�R�1�"��1Jjm�{�.:c��25��ۇ��5�J�*Aq)���We�kIT'�#OR�O�v�g�ơ]�����I��Y2&�l����AU¬����9�g�Q���ج��
ݢMV[D.^49�N��^b��`k�/P������u)�Yv���!HS����:�Z1������u��eξ�5������p��J�h�N݌��'&!8i�_�P��h�� |�Sg��j��`�
+�&��Ӧ� ������X�h��l�ҩ��b���ɱ�!+������u�A֞���|�qc�O�'�ܰ\�o��v�]y�7GJx�)�!K�Fj���)�ѝ��*Y��#6�
��1�q;�
�����<��b`nEمL���,ǡ&j�-�ӿ��^�H���vqGl�mT�PL�����'��.
��������9�q�w�I:�6����9�W�>]���(6�9a��ɜ��J������������"�}~vkk?㤢
Y�Q.��j��������PYc�R�_ !����̀�@��G-Á~�������GCjt�Z�Q��u��z�����a����W���~SR1�+=c{����ɨ�#Gn�x4�M��:�����pvR=���)fԈ������e�lPL7�h�o�[�98�Ts;������o־S]�d��~"��G��9w���5kx���>go*�o����@��y$������+� ��(����<�:`�h���g�����%�@��ih�c���X����ɐ�^�M6}�*�߼oCw�j��|�ՆȐ��Dg��!.y��(���=� ݑW%F����[�i�@��t�o&ԕ=�.��z߻̽0q/�� �|��5gB�Mg�<�fٹ����������ʣ�ʶiBC��MA��j�TZ�I�U>��{n8��G>�hr�4�ɔU�e�^M?�����n2�YP���ɓ"�om-w���Ǐ��]��K�3?읹ɥ#n[!��2��@h�j|D��L~"���%�qD�>H��(��k�}L�:|uz��t�{S#�g�7�z�t<�o��d;
���Tb�%imvj2YLvB�-�M|��O@hNb��\g8!��r{��B�]��W�'��l;G�����k{�����K�):0D!E��C�>^����N$�sP��!�Wa7�d����0#�ι���ݐTd��~�%�t�^4M?w��_o�_l�O8)�����_�	Y{J�>#k k$��s������;�H�AG<�o�jw�<Y���ǔ(�Ͱ̸�Hsx�0���i6&ă�#u��(r�/�1��l~�T��k��~���y�����Rn����E� N�}_h��,zz����|��3�wB���2{�E�'kŠ�&�+�#E_�!�ځb���[����<X�֤M,��f7��0w�
�	��f����67T�6Y���Sq��dS?���LA�Z�3R��ֶ[�E])!�$%����8���"�Ж��F��_[}�i~��ӵ������|��ɦ؜%�������׃�����������?��q�t.H�p����'i.7OZ��0��M2xy�r�1P�u�t��9��6��(ƛ��GӐ_��P�Tg_���-g�x9����|����&j��	���)��U�ċ���Z �;�`T�9u����?��h��!yhj��@�
�]��g��I<x�L�cLGn���(B(���}>�����@���T�����z�����{n:� ��b{����#���������?�d�'�.��mB[>��L#��N
�g��c!���x:�9b~���e�N6z=ħ��N2�M ���7q���玮�p�:�4�:�r���΅��G3�Cr�G��m�����s�NΦ�x�[^鞎ؐ�����	�`�Є�l��[����^9�O6��o �ЍG`�[Η�[;����K�� z�zq�'�*([m$�4vÄ�����%�����&bc�8�dc���o�ˆ�r�SU�X%��+M�����x���i����.f�؀�L�4��%)y X�6t#���PG�Ya�f���'#.(*�{7�����i�X��)g����?&�k��t&d�	c��w�b=!�2�Z��x�h�����ӽ×/���M�88n�Z���=� ����Ir�� ?_Њ_�c=��Mr\��a hr�wxx�]�Gc�0zC�m������ݝ������"���?{��U�q�7~��g���&BY�D�R��f5A�)�p�3ߍc��ՈW�?|� �;f(/��3fM)	c�>�����Nc�ˌ9.�>C�8w�#80g+б���ȶ��v�q�C�����b����r�җHZG����#(�����>?�ģ,��m��$��R|+&��`��
��`��qM��w�p�����{��ٿ�t��<|��lFm��a�7_o<dC�N~@�%��Hd#�L�˶�67�6" �7bm�g0�2V�Ol�`�[��e�?��!�6�͘$�cD�J_�8q��"	3�O[ �"�*]�)>t1cK�D�b 2�%��.�v&�(�jC�샎.�I���(*"10�$B4R�J��툰{�Y����{�D_�Ќ8���'Vd���G>��x��~�>�nk<�B`1��E���{����u^�w�7���m.ì{3j5(`�Y��4T0<�dM��:�bo��x���l	[,>���b6[L�N�:�D�9�J`LX�
�����#vs�L�����%d�>%�:���!��� R�US^Y�E��O:�$�)��Գ�w������|����=��#m��H&p٢�����N~ �����Ǌ�#����i4y��g��'7�� ���$���Iڱ����DJo~I�I��-C�s�����>�Kd��:Cu)y�R"_�S�癦&�[r�%P���gR�w]�4C�s�,���5��?G���\l[�{�a5�ce��pe�}���}��4�.�������}�@Ĩ�Dͯ� 	]i$�}5�p���J'�o��z����wd��O`a�� o������y�%`\TOc|��o��H�Q3]C'��6�Bi�w�6ز:��Tí#�9�,��;^x�&�.����%g~H5�ġ8�1��b��j4��G��@(zXM<;=R %�>��ϩ?dM�e�1\sł	.�&X�A����.izW>�68�3M�b��f�h��Q-��2JUJ��.7f+�h����7�n�=:���;|u�!��Բo��`}7�,�=f��N�%Z�&�;8^7�	BJڵ�	��ϣU���HA�J�TH�VSU�L�E��M<��+��F���ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,�]�����j @ 