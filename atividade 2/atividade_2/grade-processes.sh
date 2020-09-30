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
�      �<kt�y�60<�Fkkw�o���lYZ?bYR%�h��hgvw���zfV/[!6rJ )I��P����0��y��P\ 1�MC�G��1�~߽��]Y�'m=?�Ν�~��=�ƐtcDR2����Ӽp!��7/���ZϜx�¦�D�9�(>'O457�!?8�����F�� ����p3}�_���U-���w���I������c�P
g�JƐUe�ĝ����^�/Z� >��f��џ��������JtD��ܺ�������U��6_�[��`�-�eU�d�Dd����Q���d��(	K�H��#/)���ZG�Y�sc��"e�*�#j/��$�����@�e���KVf�+pTE(2��� �0������g��}(#$��?��.�w��G�ҏl���s����
\㰢�Y��.���߼���?O��d
eQ"W�(��|;��d%W9&��&�q�d� �x:�K����C�Q7B$� ���(�ʙ?%AL���J���P*���&�T�0+p3���&�1M6��4�Si��IEAV��C�r� ���f+���#�k#M� >%`��������Z�<��q�H)|�"�5k�&eM!q62�1���i����8�A��Z�2R[����	��A��4��+#yg�=����,pk�0XS���"R��(u��Ϸ?�X���f-cU�A�6(��F��c�c3͈�6x�Jm�R�t�V�o�	�@�T*��@)�i@�LP����7ـ~
������C�zI�S���z�v�l�N�4�$�/�&D8&_.��m�ɔ&��$!R�0{g3=s��tSচ��fT���gS�R|�wO�#��Ty��~s��y��aКZu��(S8�1�n-h��P�R����dG����tp8�k��RA��1P��T�?�a�p0�J٫��ރ��[�)�M�ĩ��j�~�]Ip�;zڜ�ϩ�J2IPʥ�ƢNSa-�/�Iz�J��}���d���ޡ�|3�xx�Y�X��d,�Bw²-�b��w�� �X��~��&�]Y@m���D`��[��G�VhACD)++2-#��]P&6%�Hr�m>#r�X�\Ib��]A��J?:S�6!'�%]�0U)@�sT��L}�L]�@fbia=�&I��n��w����ևk�Ż]���Bk�9n$6�8b�ӚE[B�����V'[�&+��]�!?����HrE:�~0�ӕ�ڂ/=�uݫz���.�CtX1�J�a�����8e� Dz���IE:Ec�S�V!3'�z�jU�I�7���Ī�����{M8Z�ڜ��0��-� �bɪ%���5�2�.I���N���iТ���R�R��#C* O;w 9�)�@���Պ���G��	<>z� ��!bC�@� F��۬��K�6e��g��f
�.9B��e𶧾��ie��.)�sul̚��&�"�S-D�+��,�0[D���k�8���R��,G9ɏrO��D.O��fe=�2y��9LL/H�JD�Ș�S� ��j�*<�������]z�/J:���NCB�]�Ҋ^��^Q02y�kC�]��7;=��4j!�����l�K?
�Dp�C&%D��[Ic��}��D��E��Q�MeY�D22a@
S���h�-���'��ڞ�f����u/��{�\����j��D9-����#�Q�oH�*?[v���8�"
&���*8���6SKC8m8�Ӓ
�*uՋd�nr�� U�pWL�A/ijF�u�*5�qG�V��(V�4'5�X���-��1SF4V��욮nz���mcc M���Q��jo��$�im|���7[���\h�A}�=��hc&��ʵ� p9�����ɐy-'�<�3ߚd[X�$>�Ĉ{#�;�`��co�~�O��ND)<&���ј��/��:�]��������x��}���د+�=���Kp��k{�|M�G���gE�o�<��Z�ѹ�ͷ�C�!a��>k�'[�$*J�Q�\(p\A֍�(�IX\i��F��ER�B��\5Ii������$�m$.�_ 籲�(��x�gM�O�*��,�ų=�d�1<	��\�0;�t�`�W��X�)r7����`8vA�!,���Hui�QcZ�zA�J�GM��-��#�v�t�vz��� 3�4��t��O��=��Jb�E��I/I���*��\$%��Q#�oꥊW�x�An�32mk��Xd��(�?�]йD��]3��s?H)�-�|�� � ��(���i��@0B�M*k�{@��Ps��[�����B�B2l��j"��.��D���Pu�
[x3�a�!�x�����2��	��@��zz��j���pQ�r�64f��M͕�Ѣ���N����܊���d�w� ��c�8���8z��f�w]�1C���XuS?�]�_�
�ޅÍ~z4YIG��ƣarqQ������2���E(�6�r��^�ߖT�����_�!}�a�f��8��?'a�:��bYrŪ�t7�9�7H8����/]�����o�A�&�0Β8	�-���x�. ��2���om�@����0����>�߂m��j�6�[fb�Y ��x�宙�Z��3�����}�x\ٗg����W� �ne^eK���o�95�[�{.�!n�y����-T���ͼ����et�QOp�	[=�O��8�g{U !��U�R�Xlxi	Lb=0�HG��r�|&�t'[&����U���!��.'I��"�l�Ji
J]�޷��"y�2�!�,�Xq� ʆ�(�OO/YIK�zV�Y��Ϳ ]Kd�$iУ�H,��<i�
�d�a>N�g���Γ��4n���Y�q��IasU��-:��O������̌,�@[�V���A79*�!���9�K*zY���2�Y��!󝾊[�ѕ�Ovt�u��L���E���f6t�*�ݼNH�7��y�נ��4�~�I�(��a�{$C��2ٻ|�{�G��xLw ��0�μ��j��e����	:hށc���?��9�U�6H>��r�EB�U�������{��u^�c�1��I���<�2�z6D��g��b�����n
�1Z���ڬ��j[�U>ٮ巘��Ʒ����kU�u�ݩ٘�w:�u�W/ ��P�@n���o}c���w�rI`�dv��:�BQ�}zT��dU��)g'�(��:�TƄI���4"�
f���t����{�d���)�eH�9�H��8٪Drx_D��Lt�"x�Y��_�9眭%Km�LM��0�R��[d �5���D։ZB+
�ntP�9��f5�x�% U�*,Z�$��~T�y_󲎁��޵��IXS<��l� ��1���]-��1h��WzF�K7�2ه۔��ME}~��tT ��`G� ���� �R�g������ 6(PQ.�����2�)!��Rs>+�j���;��`����3[&�����T$�ğ��22��2>|�TK"l�Z�gy�"�u��XP"c��{9�+�5��%�C�����,qō V���ZZ�e \	�j�3	pk{м���^�u%G��»�6�t�f+��I���h,���鄴���k��X�V�݂����XR}T������&e$j9	� ��QU!�N�P�(��(t�M�N�j����j0�tF
D�x�̜�H ��!J�l\�0O-B�%��Ʊ%&+{�$�"�Dg^�>���"�M��2�
n�MQgXb z1����{��5�]P@ma9�Z��m�@/�q�����G�	:z0ˏix�@����D���.H�9g����RG2�[����97Q�E�绊�QA9���J"��e��b�����/
Ӡz%j�8s@A�͹������T��b�{!EL:�Y�*)�����[C�p�^5�%
��؄�"D�j����e\�jҬƂ��&݈�&ǳǇ
�S����5^��ǎJG+��N\��k����9�I8#nt�ƞ��1S�:�%�l(�r�# C�}1>�f��5p{E�|���MscS٨�c�SJ�վz�ޟ�'��%�%!%�H�I��UE�2�.Hxp��A\Pb{�&&��Y�P���y�b�(1�N(!H<��0)�	2DF���V�e�1Z,ҸSG�[�)'a@����5�	�T����¸�ۘ(A���=G��ِ�D��5��UR�ȧ=�۱Y�����AgSpfb�``�th%,�-��k�BVՊPQ�鯎$�K�I�hߥ9��`���1;%��4ʦ���4��yg�L�T�,��	�W7yӯ]��SR�* Enh�g�JJ���*;��R�g��.�
�ӃɁ�eɞΕ`�����t��U��M����7v}f�A�`�e�uI��
�E�u4dDVM���cW!�,Q0����U�BBi��Le��ZM-���Q�X�`�!�e�qR�����@�j_s�7��A͒Jl?6BVe��X �F��
��B�?/����5K>�����O�����`�*�/+��8$��W�}~�<b��j.0�=��^���4쬣t�zz���v�d�t�#-��07��	ڭ��J#��%�+e�A��[�
��$$�����Yg��Zd�~��֢u�r�fz�jͶ}��A�z�=�ۉ��������l��R�Ke֠X���n�ݘX�isF1Z��u��	�ICx(^<��`Z���.xP�aq��`��4a�l1�/��\F��us��~��o:�m�~��%����\�������o}��蹣�8S8��+���w�k��lj�5����[���/��7t$�v��>������i߯�l���~�������_8r�3?����o詋�{����73S_���͇n{g���]��XX�ʥ�n<�y��ݏ>���_M�r�}7���n���O�{�å�n~����v^{��|;���g�F�8��ɯ|��	��]��6\�­�y�'מU����ݳs���v��������x#z���_��G���}���v]�J���)���޽�/����u����O���ŭ�^8����v��uK���z�텎�'N��O���;wd�y��X��mo}�����b[7\q��:�n?}���{�?�%��q[�3��>}�jmu���u�|I�s�=���9���g�<�}������u��?�ѡtY����oJ=�?{������?��E�}w��G6�]�K��7�4)���c|��z��c��q������}�y��|�犹?�-qxis`�R)v�������~�Wu�#>���y�W�Է^LN[��O�?�_ua߼sC=.|��B�y{&~1�����]?���r~��UK^����O}�?�i�X�G_^p��p��=�ԋ�_}�������]����{�W���]��y���6�]��}ɽ7n�s���]��k�[��s��go<��O�7v��������=�l��__}o�׮��]�Χ�l>��}W�|[�[��o~��_��9�*��b�o_|�{?#]=p�܎�E�����m��/ٿ�_Q��Ag��rH��]W=��m��@���༥����5�so�9�I�C�>;���7n�����_=�����͆����U*FjU�Q{Dmj�ޔii��+vP+5Kk��؛�U��Zm�ص�*F��}���s��W����y^|�5�����^&d��>�����q�=�N������)oj�EH�d:tvyKۭ#����"Wlʁ�8ϝ)>�>|Q�O�i\��
��icW4!�;��.O0#�l�v������nkF��b��g�pD�E7&�P����iv�e�`f��-�ѡ��%2���^�]�L53��O�uLt���F��/�X�&꬏�d�5@�cL�)0���sx�A;��o+��Դ����oeĉ�I�>H~��J%�W"�::?���6PL�ҡ|����Sj�/�Eő���b�$��jy;�8����Q��U�d�����LSSM�-��$X�,��9��ɯ8ʂ��@[H��ClK�q⁔V����X}^�j�S����(}�y@HO|=���:��4ʜ�9b����d���̳�����4����Yxs*WZ�JH�����Z�/AoT�Z"�U^���=��~�ڔ�s��GP���(�l�$��X�Q��<Ƭ�`�q.)vF��-�P��D�1u��-�-�:�����\����,厺�G �O/}�v��C���~�<+�����������"�"��N:���&��6�}2N�Hr�t���涱"R	R-x�q�E#�$�h����#��)5�y-���wɦ3�'R>�i��l�����H��� d�6f`J_��Wo���[z��Q��&͌������l��*�JV�Lm>N��'�XU����a�u'ԝ_6oQb����Uӫ޾�=Y�$.���]Rm�[�Aħ�����v5Ee���I�<�)����V��-��2�X�����/��ɺ�(�^6�E���aԖ�~8�B{zG�G��o��
��Oe#�3���G���Sٰ��'���1�����v) $w��&gI|Ǖ�QQ�j�M�o�`��p<���=u��T�o�p�ro��=�Q>���&�b(cw>��Mv�@32��ky
��E�Lϡ<􃨹~*@�	wS-ə'�9o_w����t48��M�i3a`{�Z�\���Y~_��5EPW��Ĩ�����m�ݳLJ�1�&[�5�3�!�!�b�xn-_	S�oB
��E|� 3U��3����� �M4.}�=v퀐��wt��׃�_�JW����F!��Έ�sT�5²^0������;�,����
F����N,��*/�r'�a�j�1���"3lMbgj����ruL�I��I�t���-���bď�L�Bܡ��25�!Ha���\h#]�k������-�ɛ!�t��P��:_��;0��=�@ۥ6%�im&P���P����}؀��/�A�u&�)zG��J(�!woB�l/Zx�2�*�#�;��H�0#N�i �+��d�`��WYV��9
�Ec�ДY�/OϽg���|�1R��*nA3_�l���]�&����i��E�H E4/�!D���ԮL�w��7}�5������FA�{qg	��f�>O+�5F�����F������"�Č��D��P)݅�(�E��\�y6��@�_)'�����&���T~#ڍo�(���6�-�`�����8��!�Օ?G��^���$O��������k�����^�ڵɩ	�����g����~�'�ul�m�`�\L�"TW�1��j�]4a�J��AJ>�]jC��Q�+��x�B�{��\E��='
��w6��7��g�+b3rw ��(�\���4PK�����-�-m	�wy�W�����]���7�=�E���2����~��ᛂM:�	��#�$}8��͝�������k�.	g2�����BO�y��C�G}��f-��j[K J[-E���ňv�א����KHY	�)��j��|�!�"W��Ġ0�=#	a]���̙ۨ������C�I�r*ҥW�)�H�O�<���6L�)�Qt2 �&%�+d!�����"�md�uZѱ��nz�������.ˇ�J�'lj��_>o��
��없��T��Y,Ա�T4/�v���tT`�Jj�h��wo/PVD?+�6��h�t7��o>�Ӽ���5�O�������'����:��'k�8<1����`�/M;�4a�|�K���i6E����'�e����ؖ���3���fg���WK�7-��~���!�Piq�^�~v�շ�.��u��s�%qX����^���Y��/N�8���$'��@N�7=@�#E�Rr ����a���Ì9�$�	l��� ~��ޖ��� 0��c~�x�k���v��}1W�B��M{w����`�kg�
��6�?|6��x�~q��&��m AFj�81����3��x���q��]\�Ed�w�m~���t�Y�-X'��___�!�r�x�ٍ��1%aS�&m��rȪ��&�ɓ^��&�"�cj���X����MZs?A�^!�e��ѿ�z�S�t�P |}�IO^F�D�7����2��0F�1j���m-NdK�9��_��v�)Tn�&a7��F�o�G�� �ߛ&�뼜�>_����@8f�
�Be?���lx*�O�����a���sJ�cč�Q��/�|*J3�?��}��'�f^�h8�^��e��u� ��T�υI���T�`����rͱ:��;�_qD������o�;�.��՘9�"�� �+��ݞwD�Wb�'�lU
��V��5�3��� U�1��<�`ްJ�X3`4L�l��>��7�P��9]����R������_*�C`]N"�(�'����,��\o�a��R�7�{�E�X��6��i����n"i�V=K6զ�|����1<36�&��&ONs��"<uW
'�ؠn]�� 6{���X��}�6pf�a�*(��u�\�'*��c��5��\}a@|��_���_�C��7؏�7\�9K�#�c�F�c�@��go���Ҍ�ϣl���GsE��m�=��˝������G�%�?�_�r���������En�׭���_�������[�u�n�׭���_�������[�u�n�׭���_�������Ka�gQ']yC�T|�H0}]�����{� "��%$�YS��(�G��*1�W����O����9�b�H8GK���xj���?'o�^"׆���f���1�KO��?�M�Ko�]����I���gK�u�#����Q�w�w�a*�O��/�Pj���=����c������ �c�q�(��������}�#�	l�h���蛻V3F������F�w�V�Y�ы�gB�˹_!`���q(�s�LW��wd�rP�2/�Wug��v>���=*i-��-G�OR��Bu�N�>��c�UU�(�.F�T��9��f����-�5�k�[�Ԇ����O
0�Y�0O~(;�����m�����Ĳ��������B|�$jc,�0K����n�1�[����n��3�N#���Rܯw�f�J�&�~��)9���x�����/��%.����I�@�'�}L��Q����z�lRuh��>��ܿ�L�W|/? eR���ӥ\�a�0/J��]�XV�4=���"��ND<�{����{lS&{,��&�O�L<�N��S	�4'��v���Lq'CN]ќgg{���k���ӱ�Й���bRQ���2��"�����R��Uڻ����p�^�0�j�H�ScڎnZ��f�XQ��q�w�i��4�?��Q��V���U�x���T_s����@v��a*~U�v�Q(`Eod;���ʬQ���c���Ý{� )��c�wo�aRQz��iNXQ����$?�_.i__r'ǟ-�V��P��'/�3�E/;'���<��/��Gg
JN��URV��9:�z����BN#{�8}n�P�0����W0SA-�NS�(�P�� ���}m�깬J��5�o��V���(^hs	���f���9H_�+ԅ�Ħ����*��Q�!V�0?8b^��Y�6~�y!��+����<��K����aã�u�����F���|�{.ҟ�z�� �C�5(Dٵ�Jf'{L����K�C� ���e�]��MUĎduSk����4�a2�]�>l@��Tgpȼh�ʹп��ػ��(u��t�t��"H��4ҩCJ��CJ!
ҭ�]��Hw#%!��3���}.N��ֹ�W��������w?�3I��pPE�tͼ�Scw*�؋�&\_��2�Zf�B�%�;e\�5�\�ʙ�^9��Z\W'Q��ll[��Ǳ=�%4|V5x����\����:������ۀ9K�
+��꼻N,��j�4`B�̀�T]���4@6��Ȱ�2��Hq���;h�t������<!q��x�F�m~f쫕6�������=`o�T�5K��`'��Hq�%�ڦ�d��~P:���T/��������i�<��Т���8��hx�aE���Ĩ���E;+�΄��{G�H��_t�l~�L�]�y�a�����m�m}t���A�u]:�dI�j�P�w�>�|a+u������1�[���Ĵ��Zf���I���u@�7=�1�,���#���k�>.9u2yW��-��I�:�t6��uap�Y
ͥ� ����ﬓC�b��i��K���BH�̮.�}�ۊ����ٝ�|?��t5/$��?nM)�_�,t��$�?�<7ǚ&6�АT���<�����&`�]�^~�?o����x���4�������
Zi!
f!aM4��u��3��p-#�� bhI!9��̟	b6�e�MM��n�����V����tnu4��� �3"�wyBl�l*�<�	��t������Y���*D>N	��v�� :[v�u}�p��G3~[M����L���J��e��/�9/敻h�*�I��<��kl<���U���ߞ���-��LH�#��Uۚ	&���YҚ�t�u$n͸m7Q�͎V#���܎A%����n��o���k�ۈ9Ǘ^�hv'P IF|i&�7O	b���2��r7Q�Ljt_�D�۞\�Q0��.#)-�╧p��6��#�UuB��1�>�1�"�H�6S�o�B�#H�V/^��Z<��g�	��S�h��nqߓ����S�B�t����l�n���@h2��W���ilˑ�2O����@��&I+p56���;��|=�:�6��j��] ���\�y�m�o�b�!�ᣗP��rj��@Pxk����D�*F�+�ϝE[p���x�A
T��:}l��e{����N����S�8n��
�H�/����p� ֵ0�+)J�����%'P���3��ੴ�8h�YԔp�ì\_(z�`��:���y�`1\�k�g���XI���RFn�,!κ�k��>:��LTe�J�|'�בrR��79x�c��m+�D�ރ\,���Yt���K���}Ѥ��K:�t�B�1�7�.�ؤ��Pɧ�l��k��OBI��?��5��Ԇ�R;ݛ��b��6��g��-���0/���UV���+?N��>�q S�|�߸Űj݋`ܳn���d~*�lng"�"��+s��ղp,�P�7̼�C��&`�)U���l[fp����U��)����U�nq!*�%��F�DۼsNp�<��Uk7P"�����3TيW5r#V�S� n������~|٫��@��]
7�#��<���9:���=�Qjd��k&�=P���&w��0���\����IK�{p�}�����u~E����I��e\m࡭%x��e�x�m�ON0���B-�f�.縡S�Y#+��%���#h[���M\��H_���-�2-�F�|;��T��.^%CS�\g���}S*.,Ю��xbAs�����d�#����<,2E��w��g��q���7��T|�)-�f��T�_y�����Pw�	VW2�߰h�u�|���H�:R���3�x���R��-`����B�OR��}�>h���N�A�Kl򟖒��j$�ב�;O.X:u'i�i�wܩH �I�K`dF(����Q�u�
�8Q~ٮ�ls���!�<��\()?��������W:�>�SAg�EdC�{^s�+[�Üv����JRe�H���R�-�<.�NwA��d���=k�ȴ
s�Kͣm�9�m	�*�z��h<���#�~�{�� ��oX}�?b�\�e�'�8���`��6c��ҁ�C0J�Tv��M�Jd+��y�g�d�ƕ��s�௴PF�a#�\x��cm���m?dȹﶞ�Pu��l��:�JF���������i�<��r��G�8&}�I�,�d�c��y^œ(%]3dt�C��ءF3�X�E>&�!V�^��2�3��&R�X$255���&�Ȇ�\��ɇ<|8-c����!	���Q7"�]Y��,��%�"Һ#����y�8X�l�8��X����2���6	/?��bnٞy!J ���T5�]܊�P)��{�sQ�R�ˑF�e+l��&@��G��:������M/~R�/GS�"��I������W8�ʰ��,#�}�v�Ӏ�[i���q�wt	+�u�9��W�{z#ql~��U�mYV�W��t��Ѳ	�m�aǀC�Z�p�!`�):���"��� ���؏B�R�7�Ί���w/_31h��%ly�6��H�4��5��0D��ϫ��_u6�'%�>�۫�`ON���ڄ�W�0iK��)��m���r��NS�k�KO��җ���ߐ�n8ն��z�}VS����2ia�K��ػ�נ����>�jC�=�2�	O����p��KA��UȎ�-��E�,���F�$��O���v�N/~|�|P�7x}*τ�ضFy���.�D�P�(���,h~�/C+B�"�>}��Ry�,��z�.G�fy����Ojؖ�ەsύ�/��r��«�Y �M9�z���j���d���%�ӡ{Z ;B8~U]m�U�}�b�����*�ކ��,��@t×�X�#[
z<88sS�7P�.�����O��yi��}p0���x�5�}KE�!cHkmi�GX4�D2�R����SH��IhVx?�<Bt�L�K[��d:k-kh&�d���#���#�P���
�4�C%(�e���b
���li��.ߡ�x���7*��.�����%6|��-��ӣZ]��$+�>,������T")6Ŷ\|ձB��ѯQ�������,7]���p��/���'�����O������_�O����g7��������w��n�ߍ���7��������w��n�ߍ���7��������w������c�oQ{b�,��������׽Sb ��9��s��"�d�p@ad��3�+ϩ�=�g�@!�v<�Y�mr?F�xe�U.��ùHj���W����͵lP�E{P�~^`����i���S��s?эgi��T�o4s��6�Xd@i��$�"M|���b5��J��=m�4T:)9��uŁ�!��ߍM9A�����ܸ�S{�����j}E6vUeU%����q�L�7����4�xB�!I����Um��_�
o�ɦ�j�"�u�D{���g�R�XQ��b�vP�Ҫ��י(X��*2�#=�h �JbOu��
����O3�& Ͳo��h��%��)%}_A;Iـ=v��m�w[�ؤu*�M|��/V��=����^����.�.WQ�\1GK:��jϼ�$�0+�r�H�y��~�d�7��*���9��P�t���J.�O2�D~Σ���s^�(�-QEQNA�\�<��4��DN�e�}=>yP�K#�ǊU��W��0�l?*n��V�m'X��+ܲ�B����!�5����������Lu�qc�R����|����!k�"��a\3
H0�������QG=
W&����YU��Ϫ
�	�|�zV� �"Әh7�1[0���HMao��y�<�R6qRг[��ճj������b\e��R�? !��7	�9�8�Z�|�y��9�ү#2�٭�*�g�b�td����'�5�Q-��`l��γ?�7��ǂ��>�1�:�8R��I�����;Ysc���7<0�+ߕ�F�i�օ����x���N󟍵X��+S}L9��o����Q�0�.}�P�x]bڶR��A�����bDG��g�F��PS��!�>�SB��q�U�C�Ь�D�t&�(����"�Ѥ:?���(@�W�L.�����<��r{�7�ޤ��������ut���8��˦��e��U��˰�Ʒ�|�g|���\���F1�XFR@�O�W��-�H�lHA]%;8k+NE�O��'�.�W��]y8ToQ�lem�k)Kfc;�	~�e0��L�� R���N��T
��e�$-�
a���;c(��{{��{���w>3�s���s�=�{�s�y��<��T��3Z\��F���+���k�2>�4:�M=�Oڹ �{��o/�Y�B��c�o���L��c=&��V%eK|]��W'���O�g�j���M��vf�=^lv��>�>��R��1+��6�1�	Է/����wunx��C#�{�S�D���ji�j�5��1g�D�8�E���6ӷ�I@m[N�{T�=�l�����|��ȋjv��%~)�����B�y�<o����pik]�!�A�m�d����ns�Jh�ڟNx/Rum�	B��E�.���]�	uE��&M_�Ql�~zǽ��$�b���o�?��G9դ[pګ�/����1�O
D�M�����v�Y%��*�NQf�3h��G�X�|*mا��)��>r�y���o��ӡ���.+��mo��"Yw�ts,�YJ�l����\���6B:����"�Y;ѽ^]� 8|�������a���҅Ur߃��e��f��X�ͅ=�S��S."l��0ed\����p��MO�=��Zq���(aѩ�6�f��%r���vv�$y�8��\����fM�J�x����CF_��B�������E���G��	]���s|+�-#o�?T:v�;~^��hW����ll�2��u ֋*���b�xՙ�AdmLé��J����a�>�F�fsS�2�{w��?":�p�+���qƄ��u�J�^�L
��ݔd���3Z����u�9T�P(�e��g�D��5&�3�v_j�w���S����:�.~���_f~	)����L~E��l�V�eee�4�H|f��+_ۓ��LQI~,鏦\G1�����~�^{��_�0�_#��Q�/�KXPӔ�9��1J$�S���Um8C.���c�n	�1�q���D�+�1BEB@%�L�o�hBg_3>C�-j�4L950c`�V�n�1�1�}Mh�P��	�i�,�0�_�BC��)������4�+�᪀^��q�ytlz�RG�$�8A�{x"��4�O�j����`6�)I�Sֻ�����}��o�K6�?�E�4�6zkyV����y�4����u�Z�yy����S&W`����>�����0�x��xh���؋���/{/�&*�5�Ъ[��N��!,��1������=ƭ@�γĖfa҇_��M�z:ri��O��ODĖ���F���~P��u��N�E�������ig~v&sH2�qv�s�֧�z~i�p�"d������a�=Yl���@��v?m���]5r�7�\S�ק	�Y�7β�3ѝ�1)w�G��Ἤ���꼘MJ :�5�FVEg�jSUA�^mqe���4����>\�	����<�J�X:�eݾ�[3����T�i��䷭��6�3��x�Ǌ�4��ɬ��m�_d���w+�d�p�_�E�X������*aM�E���^��������c`;�o���Z�F�̤�	}I<���^H�cS�+>�04h~)A	9�����z��W2�D�D��[3�3bn�w�߰(�ێ�X��y��+\����󎷘z\<��Pp�>t��l*K����yG7��m&y���e��2�6KW��O�_4|@;#�@��q��{��t��h�ѷI}vW[�l���>�a�REH��D��?�����7@뿿��u8�x�ء��6 ��lqc�O���Ξ�_�3N�em�6���A,"������]��eRWj�/�P�ESD<���� �&�0�q��%��o9��3��b}LFg��:c��l�ʿX���n�����1��h�Ӎی�X>a2�7W!���6�z`l�8R���P[NM�6�s�sbc�q_�k�A��u���E���Ll'+Q=f��/�W��a>.�7�ex^N7f�z�> ��|�|�����9s�'ē��6=�\���&�G_���ֈ�$td�N��������.�W�����zl�������.��g�L�Fn�4و�1�VJ�9�g�bn��2�T	�1��A ��)���k̗㛵�NiT�I�\�G~s
��}�-�qej�$Ā�IU> ����df[�����m���g	����;�_��_/���ZL[Xl�O�B�u�ПlB�����qb��蝑x����5o�b���V�:�rݠ@TW�Jĸ�E"�������1�"��9�I��HI�;��W�'	{UڊB��D��6g5L�d=�e�m0�O�U�TYvܐ��(�ʓGQ^���5E'������nB�8�s��֣�!b_n\�[�V���c���G�B�B�_�
��ijD����EM	���I8�]�����V�H��M�'��P�q��8Z��o�!}{LJ��M���z��6��pOw9uG\oB���D�h�Ǽ����_����&�_�7��a�?�����Q��W���eg@ kr��H	�{0��	_�ū��#~�M�V���:�ِ� g$Ci����(��`�uGV�QX؆�e����̬Z&ָa /Gң�Cb=1�?Z:#}�X;�
c-�f_b�>lm�畐��Ϗ��i�`�� ��$�.�7{�"�E!���c�2l(}��M�)�
%ދ���-s��~h#}�!/���[^3����<	'�p�E����C!����5"���NI��NI��`띂�s
�:[�eݓ�+QK҂� -J{�7����8Kr ��:���4�?� k�]��ˣ�췪��*lUU��~�n	}o �����n{����V�ġ?S65���]_ee����l�)@.F�Y[��THC8 ���z�1@R��wY�bmW� N��Ⱥ���8��Ñ̉Q�$+p '����e$��ߝ#�����-���A$��I�'o~��d��4�`�1X2}XY�Q �q$�&,X�T��LM�m�[C.��A��%-W$���[�%����G/7�ՓVs��&0(2��x#���B��e���A�"�#�e��"��ܜ��M�)�����TPATPATPATPATPATPAT�_�_��{K �  