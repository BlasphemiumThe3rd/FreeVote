#!/bin/bash
#
# programa de instalación y personalización del paquete evote
#
# <C> Juan Antonio Martínez Junio-2000

cd `dirname $0`
BASE=`pwd`
PROGRAM=`basename $0`

if [ ! -f $BASE/config ]; then
	echo "No encuentro fichero de configuración. Instalación Abortada"
	exit 1
fi

. $BASE/config

sqlquery () {
        psql -d $DBNAME -F : -h $DBHOST -p $DBPORT -t -A -q -U $DBUSER -c "$*"
} 

if [ "$1" = "--do-all" ]; then
echo "Free-Vote. Proceso de instalacion"
$BASE/$PROGRAM --restart-db
$BASE/$PROGRAM --compile-doc
$BASE/$PROGRAM --register-sysop
$BASE/$PROGRAM --install-files
$BASE/$PROGRAM --clean-doc
echo "Instalacion completa."
exit 0
fi

if [ "$1" = "--restart-db" ]; then
echo "Regenerando database..."
dropdb $DBNAME -U $DBUSER -h $DBHOST -p $DBPORT
createdb $DBNAME -U $DBUSER -h $DBHOST -p $DBPORT
createlang -U postgres -L /usr/lib/pgsql -h $DBHOST -p $DBPORT plpgsql $DBNAME
psql $DBNAME -U $DBUSER -h $DBHOST -p $DBPORT -f lib/database.sql
echo "Hecho."
exit 0
fi

if [ "$1" = "--clean-doc" ]; then
echo "Limpiando directorios..."
rm -f $BASE/doc/*.{ps,eps,html}
echo "Hecho."
exit 0
fi

if [ "$1" = "--compile-doc" ]; then
echo "Generando documentacion...."
( 
	cd $BASE/doc
	# Convierte gifs en EPS
	for i in *.gif ; do
		tmpfile=$TMPDIR/gif2ps.$$
		echo procesando $i
		gif2ps -q -x $i > $tmpfile  
		ps2epsi $tmpfile `echo $i | sed -e 's/\.gif/.eps/g'`	
		rm -f $tmpfile
	done
	# Genera HTML's a partir del SGML
	sgml2html --charset=latin documentacion.sgml 
	sgml2html --charset=latin article.sgml 
	# Genera Docs en formato PostScript
	sgml2latex --charset=latin --papersize=a4 --language=es --output=ps documentacion.sgml
	sgml2latex --charset=latin --papersize=a4 --language=es --output=ps article.sgml
)
echo "Hecho."
exit 0
fi

if [ "$1" = "--install-files" ]; then
# Generamos directorios
echo -n "Creando directorios..."
mkdir -p $INSTALLDIR $INSTALLDIR/doc $INSTALLDIR/templates $BINDIR $LOGDIR $BACKUPDIR
echo "Hecho."

# Copiamos ficheros
echo -n "Copiando ficheros...."
# truquillo para especificar el protocolo (http o https)
ESCURL=`echo $WEBURL | sed -e 's/\//\\\\\//g'`
SECUREURL=$ESCURL
[ $USE_HTTPS -eq 1 ] && SECUREURL=`echo $ESCURL | sed 's/http:/https:/g'`
for i in $BASE/html/* ; do 
	cat $i | sed -e "s/WEBURL/$ESCURL/g" -e "s/SECUREURL/$SECUREURL/g" > $INSTALLDIR/`basename $i`
done
cp $BASE/doc/* $INSTALLDIR/doc
cp $BASE/lib/database.sql $INSTALLDIR
cp $BASE/COPYING $INSTALLDIR
cp $BASE/bin/* $BINDIR
cp $BASE/config $BINDIR/evote_config
cp $BASE/lib/* $BACKUPDIR 2> /dev/null
cp $BASE/lib/templates/* $INSTALLDIR/templates
chmod +x $BINDIR/evote_*

echo "Hecho."

# Personalizamos instalación
echo -n "Personalizando...."
(
echo "<?";
# truco cutre para "php-izar" un script de asignaciones shell
sed 	-e 's/#.*//g' \
	-e '/^[ 	]*$/d' \
	-e '/DBPASSWD=/d' \
	-e '/DBUSER=/d' \
	-e 's/"//g' \
	-e 's/^[ 	]*/$/g' \
	-e 's/[ 	]*=[ 	]*/ = "/g' \
	-e 's/[ 	]*$/" ;/g' $BASE/config
echo "?>"
) > $INSTALLDIR/config.php3

# compilamos el programa para encriptar
	gcc -O2 $BASE/lib/crypt.c -o $BINDIR/evote_crypt -lcrypt

echo "Hecho."
echo -n "Creando datos para crontab y httpd.conf... "

# creamos el fichero de crontab
rm -f $BACKUPDIR/crontab.evote
echo "0 0 * * * $BINDIR/evote_cron.sh daily" >> $BACKUPDIR/crontab.evote
echo "0 0 * * 1 $BINDIR/evote_cron.sh weekly" >> $BACKUPDIR/crontab.evote
echo "Hecho."
# creamos datos de configuracion para el apache
cat << __EOF > $BACKUPDIR/httpd.conf.evote
#
# httpd.conf tags for Free-Vote package
#
# Alias /free-vote $INSTALLDIR/
<Directory "$INSTALLDIR">
	Options Indexes Includes FollowSymLinks ExecCGI
	AllowOverride None
	SetEnv DBUSER $DBUSER
	SetEnv DBPASSWD $DBPASSWD
	Order allow,deny
	Allow from all
</Directory>
__EOF

echo "Hecho."

# generando tgz...
echo -n "Generando fichero de backup..."
# eliminamos contraseña !!!no la vamos a exportar, vamos anda!!!
mv $BASE/config /tmp/config.$$
sed 's/DBPASSWD=.*/DBPASSWD=/g' /tmp/config.$$ > $BASE/config
tar zcf $INSTALLDIR/evote.tgz .
mv -f /tmp/config.$$ $BASE/config
echo "Hecho."

exit 0

fi

if [ "$1" = "--register-sysop" ]; then
	echo "Registrando administrador de la base de datos...."
	mkdir -p $BACKUPDIR

# compilamos el programa para encriptar
	gcc -O2 $BASE/lib/crypt.c -o /tmp/crypt -lcrypt
	key=`/tmp/crypt $ADMIN_EMAIL`
	sqlkey=`/tmp/crypt $key $key`
	rm -f /tmp/crypt /tmp/crypt.c

	com="INSERT INTO usuarios \
		(groupid,passwd,nombre,apellidos,direccion,telefono,email) \
	VALUES ( 6,'$sqlkey','$ADMIN_FIRSTNAME','$ADMIN_LASTNAME','$ADMIN_ADDRESS','$ADMIN_PHONE','$ADMIN_EMAIL');"
	sqlquery $com 2> /dev/null
	if [ $? -ne 0 ]; then
	    echo "Error en INSERT: Posiblemente el usuario está ya registrado"
	    echo "Deberá proceder a la instalación manualmente"
	    exit 1
	fi
	com="SELECT userid FROM usuarios WHERE email='$ADMIN_EMAIL';"
	userid=`sqlquery $com`
	echo "Hecho. "
	echo "El userid del administrador es $userid"
	echo "La contraseña es $key"
	echo "La dirección de correo es $ADMIN_EMAIL"
	# guardamos datos en fichero del usuario
	cp $BASE/config $BACKUPDIR/evote_config
	echo "# Datos del administrador generados en la database" >> $BACKUPDIR/evote_config
	echo "ADMIN_USERID=$userid"	>> $BACKUPDIR/evote_config
	echo "ADMIN_PASSWD=$key"	>> $BACKUPDIR/evote_config
	echo "Una copia de los datos de instalación y configuración se ha guardado en $BACKUPDIR/evote_config"
	exit 0
fi

# si llega hasta aquí es que no han especificado parametros
echo "Uso: "
echo "	$0 --do-all 		Proceso de instalación completo"
echo "	$0 --restart-db	Reinicia la base de datos"
echo "	$0 --install-files 	Configura e instala los ficheros"
echo "	$0 --register-sysop 	Registra administrador en la database"
echo "	$0 --compile-doc 	Compila ficheros SGML de documentacion"
echo "	$0 --clean-doc 	Limpia directorio de documentacion"

