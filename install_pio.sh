#!/usr/bin/env bash

# Based from https://install.prediction.io/install.sh.
# Tweaked:
#   Don't ask database; Use Elasticsearch & HBase only;
#   Remove duplicates between interactive or not. Use interactive only;
#   Install Hadoop 2.4 for using hdfs;
#   HBASE 1.1.2 buggy, so replaced with 1.1.4
#     (https://github.com/actionml/cluster-setup/blob/master/small-ha-cluster-setup.md#requirements)
#   Spark's Hadoop Version changed to 2.4 from 2.6, for compatibility with spark-ec2

OS=`uname`
PIO_VERSION=0.9.6
SPARK_VERSION=1.6.0
HADOOP_VERSION=2.4.1
# Looks like support for Elasticsearch 2.0 will require 2.0 so deferring
ELASTICSEARCH_VERSION=1.7.3
HBASE_VERSION=1.1.4 # 
PIO_DIR=$HOME/PredictionIO
USER_PROFILE=$HOME/.profile
PIO_FILE=PredictionIO-${PIO_VERSION}.tar.gz
TEMP_DIR=/tmp

DISTRO_DEBIAN="Debian/Ubuntu"
DISTRO_OTHER="Other"

ES_HB="Elasticsearch + HBase"

# Ask a yes/no question, with a default of "yes".
confirm () {
  echo -ne $@ "[Y/n] "
  read -r response

  case ${response} in
    [yY][eE][sS]|[yY]|"")
      true
      ;;
    [nN][oO]|[nN])
      false
      ;;
    *)
      confirm $@
      ;;
  esac
}

echo -e "\033[1;32mWelcome to PredictionIO $PIO_VERSION!\033[0m"

# Detect OS
if [[ "$OS" = "Darwin" ]]; then
  echo "Mac OS detected!"
  SED_CMD="sed -i ''"
elif [[ "$OS" = "Linux" ]]; then
  echo "Linux OS detected!"
  SED_CMD="sed -i"
else
  echo -e "\033[1;31mYour OS $OS is not yet supported for automatic install :(\033[0m"
  echo -e "\033[1;31mPlease do a manual install!\033[0m"
  exit 1
fi

if [[ $USER ]]; then
  echo "Using user: $USER"
else
  echo "No user found - this is OK!"
fi

# Interactive
while true; do
  echo -e "\033[1mWhere would you like to install PredictionIO?\033[0m"
  read -e -p "Installation path ($PIO_DIR): " pio_dir
  pio_dir=${pio_dir:-$PIO_DIR}

  read -e -p "Vendor path ($pio_dir/vendors): " vendors_dir
  vendors_dir=${vendors_dir:-$pio_dir/vendors}

  read -e -p "Private DNS (localhost): " private_dns
  ssh -q ${private_dns} exit
  if [[ $? -ne 0 ]] ; then
    echo "$private_dns should be accessible with 'ssh ${private_dns}'"
    exit 1
  fi

  if confirm "Receive updates?"; then
    guess_email=''
    if hash git 2>/dev/null; then
      # Git installed!
      guess_email=$(git config --global user.email)
    fi

    if [ -n "${guess_email}" ]; then
      read -e -p "Email (${guess_email}): " email
    else
      read -e -p "Enter email: " email
    fi
    email=${email:-$guess_email}

    url="https://direct.prediction.io/$PIO_VERSION/install.json/install/install/$email/"
    curl --silent ${url} > /dev/null
  fi

  spark_dir=${vendors_dir}/spark-${SPARK_VERSION}
  hadoop_dir=${vendors_dir}/hadoop-${HADOOP_VERSION}
  elasticsearch_dir=${vendors_dir}/elasticsearch-${ELASTICSEARCH_VERSION}
  hbase_dir=${vendors_dir}/hbase-${HBASE_VERSION}
  zookeeper_dir=${vendors_dir}/zookeeper

  echo "--------------------------------------------------------------------------------"
  echo -e "\033[1;32mOK, looks good!\033[0m"
  echo "You are going to install PredictionIO to: $pio_dir"
  echo -e "Vendor applications will go in: $vendors_dir\n"
  echo "Spark: $spark_dir"
  echo "Elasticsearch: $elasticsearch_dir"
  echo "HBase: $hbase_dir"
  echo "ZooKeeper: $zookeeper_dir"
  echo "Hadoop: $hadoop_dir"
  echo "--------------------------------------------------------------------------------"
  if confirm "\033[1mIs this correct?\033[0m"; then
    break;
  fi
done

echo -e "\033[1mSelect your linux distribution:\033[0m"
select distribution in "$DISTRO_DEBIAN" "$DISTRO_OTHER"; do
  case $distribution in
    "$DISTRO_DEBIAN")
      break
      ;;
    "$DISTRO_OTHER")
      break
      ;;
    *)
      ;;
  esac
done

# Java Install
if [[ ${OS} = "Linux" ]] ; then
  case ${distribution} in
    "$DISTRO_DEBIAN")
      echo -e "\033[1;36mStarting Java install...\033[0m"

      echo -e "\033[33mThis script requires superuser access!\033[0m"
      echo -e "\033[33mYou will be prompted for your password by sudo:\033[0m"

      sudo apt-get update
      sudo apt-get install openjdk-7-jdk libgfortran3 python-pip -y
      sudo pip install predictionio

      echo -e "\033[1;32mJava install done!\033[0m"
      break
      ;;
    "$DISTRO_OTHER")
      echo -e "\033[1;31mYour distribution not yet supported for automatic install :(\033[0m"
      echo -e "\033[1;31mPlease install Java manually!\033[0m"
      exit 2
      ;;
    *)
      ;;
  esac
fi

# Try to find JAVA_HOME
echo "Locating JAVA_HOME..."
if [[ "$OS" = "Darwin" ]]; then
  JAVA_VERSION=`echo "$(java -version 2>&1)" | grep "java version" | awk '{ print substr($3, 2, length($3)-2); }'`
  JAVA_HOME=`/usr/libexec/java_home`
elif [[ "$OS" = "Linux" ]]; then
  JAVA_HOME=$(readlink -f /usr/bin/javac | sed "s:/bin/javac::")
fi
echo "Found: $JAVA_HOME"

# Check JAVA_HOME
while [ ! -f "$JAVA_HOME/bin/javac" ]; do
  echo -e "\033[1;31mJAVA_HOME is incorrect!\033[0m"
  echo -e "\033[1;33mJAVA_HOME should be a directory containing \"bin/javac\"!\033[0m"
  read -e -p "Please enter JAVA_HOME manually: " JAVA_HOME
done;

if [ -n "$JAVA_VERSION" ]; then
  echo "Your Java version is: $JAVA_VERSION"
fi
echo "JAVA_HOME is now set to: $JAVA_HOME"

# PredictionIO
echo -e "\033[1;36mStarting PredictionIO setup in:\033[0m $pio_dir"
cd ${TEMP_DIR}
if [[ ! -e ${PIO_FILE} ]]; then
  echo "Downloading PredictionIO..."
  curl -OL https://github.com/PredictionIO/PredictionIO/releases/download/v${PIO_VERSION}/${PIO_FILE}
fi
tar zxf ${PIO_FILE}
rm -rf ${pio_dir}
mv PredictionIO-${PIO_VERSION} ${pio_dir}

if [[ $USER ]]; then
  chown -R $USER ${pio_dir}
fi

echo "Updating ~/.profile to include: $pio_dir"
PATH=$PATH:${pio_dir}/bin
echo "export PATH=\$PATH:$pio_dir/bin" >> ${USER_PROFILE}

echo -e "\033[1;32mPredictionIO setup done!\033[0m"

mkdir ${vendors_dir}

# Spark
echo -e "\033[1;36mStarting Spark setup in:\033[0m $spark_dir"
if [[ ! -e spark-${SPARK_VERSION}-bin-hadoop2.4.tgz ]]; then
  echo "Downloading Spark..."
  curl -O http://d3kbcqa49mib13.cloudfront.net/spark-${SPARK_VERSION}-bin-hadoop2.4.tgz
fi
tar xf spark-${SPARK_VERSION}-bin-hadoop2.4.tgz
rm -rf ${spark_dir}
mv spark-${SPARK_VERSION}-bin-hadoop2.4 ${spark_dir}

echo "Updating: $pio_dir/conf/pio-env.sh"
${SED_CMD} "s|SPARK_HOME=.*|SPARK_HOME=$spark_dir|g" ${pio_dir}/conf/pio-env.sh

echo -e "\033[1;32mSpark setup done!\033[0m"


# Elasticsearch
echo -e "\033[1;36mStarting Elasticsearch setup in:\033[0m $elasticsearch_dir"
if [[ ! -e elasticsearch-${ELASTICSEARCH_VERSION}.tar.gz ]]; then
  echo "Downloading Elasticsearch..."
  curl -O https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-${ELASTICSEARCH_VERSION}.tar.gz
fi

tar zxf elasticsearch-${ELASTICSEARCH_VERSION}.tar.gz
rm -rf ${elasticsearch_dir}
mv elasticsearch-${ELASTICSEARCH_VERSION} ${elasticsearch_dir}

echo "Updating: $elasticsearch_dir/config/elasticsearch.yml"
echo 'network.host: 127.0.0.1' >> ${elasticsearch_dir}/config/elasticsearch.yml

echo "Updating: $pio_dir/conf/pio-env.sh"
${SED_CMD} "s|PIO_STORAGE_REPOSITORIES_METADATA_SOURCE=PGSQL|PIO_STORAGE_REPOSITORIES_METADATA_SOURCE=ELASTICSEARCH|" ${pio_dir}/conf/pio-env.sh
${SED_CMD} "s|PIO_STORAGE_REPOSITORIES_MODELDATA_SOURCE=PGSQL|PIO_STORAGE_REPOSITORIES_MODELDATA_SOURCE=LOCALFS|" ${pio_dir}/conf/pio-env.sh
${SED_CMD} "s|PIO_STORAGE_REPOSITORIES_EVENTDATA_SOURCE=PGSQL|PIO_STORAGE_REPOSITORIES_EVENTDATA_SOURCE=HBASE|" ${pio_dir}/conf/pio-env.sh
${SED_CMD} "s|PIO_STORAGE_SOURCES_PGSQL|# PIO_STORAGE_SOURCES_PGSQL|" ${pio_dir}/conf/pio-env.sh
${SED_CMD} "s|# PIO_STORAGE_SOURCES_LOCALFS|PIO_STORAGE_SOURCES_LOCALFS|" ${pio_dir}/conf/pio-env.sh
${SED_CMD} "s|# PIO_STORAGE_SOURCES_ELASTICSEARCH_TYPE|PIO_STORAGE_SOURCES_ELASTICSEARCH_TYPE|" ${pio_dir}/conf/pio-env.sh
${SED_CMD} "s|# PIO_STORAGE_SOURCES_ELASTICSEARCH_HOME=.*|PIO_STORAGE_SOURCES_ELASTICSEARCH_HOME=$elasticsearch_dir|" ${pio_dir}/conf/pio-env.sh

echo -e "\033[1;32mElasticsearch setup done!\033[0m"

# HBase
echo -e "\033[1;36mStarting HBase setup in:\033[0m $hbase_dir"
if [[ ! -e hbase-${HBASE_VERSION}-bin.tar.gz ]]; then
  echo "Downloading HBase..."
  curl -O http://archive.apache.org/dist/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz
fi
tar zxf hbase-${HBASE_VERSION}-bin.tar.gz
rm -rf ${hbase_dir}
mv hbase-${HBASE_VERSION} ${hbase_dir}

echo "Creating default site in: $hbase_dir/conf/hbase-site.xml"
cat <<EOF > ${hbase_dir}/conf/hbase-site.xml
<configuration>
  <property>
    <name>hbase.rootdir</name>
    <value>hdfs://${private_dns}:9000/hbase</value>
  </property>
  <property>
    <name>hbase.cluster.distributed</name>
    <value>true</value>
  </property>
  <property>
    <name>hbase.zookeeper.property.dataDir</name>
    <value>hdfs://${private_dns}:9000/zookeeper</value>
  </property>
  <property>
    <name>hbase.zookeeper.quorum</name>
    <value>${private_dns}</value>
  </property>
  <property>
    <name>hbase.zookeeper.property.clientPort</name>
    <value>2181</value>
  </property>
</configuration>
EOF
echo "${private_dns}" > ${hbase_dir}/conf/regionservers

echo "Updating: $hbase_dir/conf/hbase-env.sh to include $JAVA_HOME"
${SED_CMD} "s|# export JAVA_HOME=/usr/java/jdk1.6.0/|export JAVA_HOME=$JAVA_HOME|" ${hbase_dir}/conf/hbase-env.sh

echo "Updating: $pio_dir/conf/pio-env.sh"
${SED_CMD} "s|# PIO_STORAGE_SOURCES_HBASE|PIO_STORAGE_SOURCES_HBASE|" ${pio_dir}/conf/pio-env.sh
${SED_CMD} "s|PIO_STORAGE_SOURCES_HBASE_HOME=.*|PIO_STORAGE_SOURCES_HBASE_HOME=$hbase_dir|" ${pio_dir}/conf/pio-env.sh
${SED_CMD} "s|# HBASE_CONF_DIR=.*|HBASE_CONF_DIR=$hbase_dir/conf|" ${pio_dir}/conf/pio-env.sh

echo -e "\033[1;32mHBase setup done!\033[0m"

# Hadoop
echo -e "\033[1;36mStarting Hadoop setup in:\033[0m $hadoop_dir"
if [[ ! -e hadoop-${HADOOP_VERSION}.tar.gz ]]; then
  echo "Downloading Hadoop..."
  curl -O http://archive.apache.org/dist/hadoop/core/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz
fi
tar zxf hadoop-${HADOOP_VERSION}.tar.gz
rm -rf ${hadoop_dir}
mv hadoop-${HADOOP_VERSION} ${hadoop_dir}

echo "Updating: $hadoop_dir/etc/hadoop/hadoop-env.sh to include $JAVA_HOME"
${SED_CMD} "s|export JAVA_HOME=.*|export JAVA_HOME=$JAVA_HOME|" $hadoop_dir/etc/hadoop/hadoop-env.sh

echo "export HADOOP_COMMON_LIB_NATIVE_DIR=${hadoop_dir}/lib/native" >> $hadoop_dir/etc/hadoop/hadoop-env.sh
echo "export HADOOP_OPTS='-Djava.library.path=${hadoop_dir}/lib'" >> $hadoop_dir/etc/hadoop/hadoop-env.sh


cat <<EOF > ${hadoop_dir}/etc/hadoop/core-site.xml
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://${private_dns}:9000</value>
  </property>
</configuration>
EOF

cat <<EOF > ${hadoop_dir}/etc/hadoop/hdfs-site.xml
<configuration>
  <property>
    <name>dfs.name.dir</name>
    <value>${hadoop_dir}/dfs/name</value>
    <final>true</final>
  </property>
  <property>
    <name>dfs.data.dir</name>
    <value>${hadoop_dir}/dfs/data</value>
    <final>true</final>
  </property>
  <property>
    <name>dfs.replication</name>
    <value>1</value>
  </property>
</configuration>
EOF


echo "${private_dns}" > $hadoop_dir/etc/hadoop/slaves

echo "Format hdfs namenode"
$hadoop_dir/bin/hdfs namenode -format

echo -e "\033[1;32mHadoop setup done!\033[0m"



echo "Updating permissions on: $vendors_dir"

if [[ $USER ]]; then
  chown -R $USER ${vendors_dir}
fi

echo -e "\033[1;32mInstallation done!\033[0m"


echo "--------------------------------------------------------------------------------"
echo -e "\033[1;32mInstallation of PredictionIO $PIO_VERSION complete!\033[0m"
echo -e "\033[1;32mPlease follow documentation at http://docs.prediction.io/start/download/ to download the engine template based on your needs\033[0m"
echo -e
echo -e "\033[1;33mCommand Line Usage Notes:\033[0m"
echo -e "To start PredictionIO and dependencies, run: '\033[1m${hadoop_dir}/sbin/start-dfs.sh\033[0m' and then,"
echo -e "To start PredictionIO and dependencies, run: '\033[1mpio-start-all\033[0m'"
echo -e "To check the PredictionIO status, run: '\033[1mpio status\033[0m'"
echo -e "To train/deploy engine, run: '\033[1mpio [train|deploy|...]\033[0m' commands"
echo -e "To stop PredictionIO and dependencies, run: '\033[1mpio-stop-all\033[0m'"
echo -e ""
echo -e "Please report any problems to: \033[1;34msupport@prediction.io\033[0m"
echo "--------------------------------------------------------------------------------"
