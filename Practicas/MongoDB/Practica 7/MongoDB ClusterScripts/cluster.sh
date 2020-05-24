#!/bin/bash

#############################################
######## Parámetros Configurables ###########
#############################################

# $1 -> Número de particiones.
numberOfShards=$1;

# $2 -> Factor de réplica de las particiónes.
replicaSetFactor=$2;

# $3 -> Tamaño de los chunk.
chunkSize=$3;

#############################################
######## Servidores de Configuración ########
#############################################

# Borrado y creación de las carpetas de datos.
rm -rf configurationServer[1-3]
mkdir configurationServer1 configurationServer2 configurationServer3

# Levantamos los Servidores de Configuración, estos forman parte de un mismo Replica Set.
mongod --configsvr --replSet configurationServerReplicaSet --dbpath configurationServer1 --port 26050 --fork --logpath configurationServer1/logFile --logappend
mongod --configsvr --replSet configurationServerReplicaSet --dbpath configurationServer2 --port 26051 --fork --logpath configurationServer1/logFile --logappend
mongod --configsvr --replSet configurationServerReplicaSet --dbpath configurationServer3 --port 26052 --fork --logpath configurationServer1/logFile --logappend

# Creamos un fichero JavaScript para automatizar la creación del Replica Set de los servidores de configuración.
cmd="
conf = { 
	_id: 'configurationServerReplicaSet', 
	members: [ { _id: 0, host: 'localhost:26050' } , {_id: 1, host: 'localhost:26051' }, { _id: 2, host: 'localhost:26052' } ]
};
rs.initiate(conf);
rs.status();
"
echo "$cmd" > configurationServerReplicaSetCommands.js

# Ejecutamos en una terminal diferente una conexión al nodo primario del Replica Set de los Servidores de Configuración.
gnome-terminal --title="Configuration Server" -x bash -c "mongo --port 26050  --shell configurationServerReplicaSetCommands.js"

#############################################
######## Servidores de Partición ############
#############################################

interval=100;
basePort=27000;

# Shard Number
for sn in `seq $numberOfShards`
do

	# Reseteamos el contador.
	counter=0;

	# Reseteamos los miembros del Replica Set.
	replicaSetMembers="";

	# Replica Set Factor
	for rsf in `seq $replicaSetFactor`
	do

		# Número de puerto.		
		let port=basePort+interval+counter;

		# Borrado y creación de las carpetas de datos.
		rm -rf "partition${sn}_${rsf}";
		mkdir "partition${sn}_${rsf}";

		# Levantamos los Servidores de Partición, estos se agrupan en varios Replica Set.
		mongod --shardsvr --replSet "partition${sn}" --dbpath "partition${sn}_${rsf}" --logpath "partition${sn}_${rsf}/logFile" --port $port --fork --logappend --oplogSize 50;

		# Añadimos un mirembro al Replica Set.
		replicaSetMembers+="{_id:$counter,host:'localhost:$port'},";

		# Incrementamos el contador.
		let counter=counter+1;

	done
	
	# Puerto del nodo primario de la partición.
	let portOfPrimary=basePort+interval;

	# Quitamos la última coma.
	let size=${#replicaSetMembers}-1;
	replicaSetMembers=${replicaSetMembers:0:$size}

	# Creamos un fichero JavaScript para automatizar la creación del Replica Set 1 de los Servidores de Partición.
	cmd="config = { _id: 'partition${sn}', members: [ $replicaSetMembers ] }; rs.initiate(config); rs.status();"
	echo "$cmd" > partition${sn}Commands.js;

	# Ejecutamos en una terminal diferente una conexión al nodo primario del Replica Set correspondiente.
	gnome-terminal --title="Partition${sn} Server" -x bash -c "mongo --port $portOfPrimary --shell partition${sn}Commands.js";

	# Particiones a añadir.
	shardsToAdd+="sh.addShard('partition${sn}/localhost:$portOfPrimary'); ";

	# Incrementamos el intervalo.
	let interval=interval+100;

done

#################################################
######## Servidores de Enrutamiento #############
#################################################

# Borrado y creación de los ficheros de datos.
rm mongos
echo "" > mongos

# Levantamos un Servidor de Enrutamiento.
mongos --configdb configurationServerReplicaSet/localhost:26050,localhost:26051,localhost:26052 --fork --logappend --logpath mongos

# Creamos un fichero JavaScript para automatizar la creación de una colección funciona con datos particionados.
cmd="db = db.getSiblingDB('config'); db.settings.save({ _id: 'chunksize', value: $chunkSize}); db = db.getSiblingDB('local'); $shardsToAdd sh.status();";
echo "$cmd" > mongosServerCommands.js

# Ejecutamos en una terminal diferente una conexión al nodo que hace de Servidor de Enrutamiento.
gnome-terminal --title="Mongos Server" -x bash -c "mongo --shell mongosServerCommands.js"

