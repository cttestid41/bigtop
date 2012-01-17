# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

class hadoop {

  /**
   * Common definitions for hadoop nodes.
   * They all need these files so we can access hdfs/jobs from any node
   */
  class common {
    file {
      "/etc/hadoop/conf/hadoop-env.sh":
        content => template('hadoop/hadoop-env.sh'),
        require => [Package["hadoop"]],
    }

    file {
      "/etc/default/hadoop":
        content => template('hadoop/hadoop'),
        require => [Package["hadoop"]],
    }

    package { "hadoop":
      ensure => latest,
      require => Package["jdk"],
    }

    #FIXME: package { "hadoop-native":
    #  ensure => latest,
    #  require => [Package["hadoop"]],
    #}
  }

  class common-yarn inherits common {
    package { "hadoop-yarn":
      ensure => latest,
      require => [Package["jdk"], Package["hadoop"]],
    }
 
    file {
      "/etc/hadoop/conf/yarn-site.xml":
        content => template('hadoop/yarn-site.xml'),
        require => [Package["hadoop"]],
    }

    file { "/etc/hadoop/conf/container-executor.cfg":
      content => template('hadoop/container-executor.cfg'), 
      require => [Package["hadoop"]],
    }
  }

  class common-hdfs inherits common {
    package { "hadoop-hdfs":
      ensure => latest,
      require => [Package["jdk"], Package["hadoop"]],
    }
 

    file {
      "/etc/hadoop/conf/core-site.xml":
        content => template('hadoop/core-site.xml'),
        require => [Package["hadoop"]],
    }

    file {
      "/etc/hadoop/conf/hdfs-site.xml":
        content => template('hadoop/hdfs-site.xml'),
        require => [Package["hadoop"]],
    }
  }

  class common-mapred-app inherits common-hdfs {
    package { "hadoop-mapreduce":
      ensure => latest,
      require => [Package["jdk"], Package["hadoop"]],
    }

    file {
      "/etc/hadoop/conf/mapred-site.xml":
        content => template('hadoop/mapred-site.xml'),
        require => [Package["hadoop"]],
    }

    file { "/etc/hadoop/conf/taskcontroller.cfg":
      content => template('hadoop/taskcontroller.cfg'), 
      require => [Package["hadoop"]],
    }
  }

  define datanode ($namenode_host, $namenode_port, $port = "50075", $auth = "simple", $dirs = ["/tmp/data"]) {

    $hadoop_namenode_host = $namenode_host
    $hadoop_namenode_port = $namenode_port
    $hadoop_datanode_port = $port
    $hadoop_security_authentication = $auth

    include common-hdfs

    package { "hadoop-hdfs-datanode":
      ensure => latest,
      require => Package["jdk"],
    }

    if ($hadoop_security_authentication == "kerberos") {
      #FIXME: package { "hadoop-sbin":
      #  ensure => latest,
      #  require => [Package["hadoop"]],
      #}
    }

    service { "hadoop-hdfs-datanode":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-hdfs-datanode"], File["/etc/hadoop/conf/core-site.xml"], File["/etc/hadoop/conf/hdfs-site.xml"], File["/etc/hadoop/conf/hadoop-env.sh"]],
      require => [ Package["hadoop-hdfs-datanode"], File[$dirs] ],
    }

    file { $dirs:
      ensure => directory,
      owner => hdfs,
      group => hdfs,
      mode => 755,
      require => [Package["hadoop-hdfs"]],
    }
  }

  define create_hdfs_dirs($hdfs_dirs_meta) {
    $user = $hdfs_dirs_meta[$title][user]
    $perm = $hdfs_dirs_meta[$title][perm]

    exec { "HDFS init $title":
      user => "hdfs",
      command => "/bin/bash -c 'hadoop fs -mkdir $title && hadoop fs -chmod $perm $title && hadoop fs -chown $user $title'",
      unless => "/bin/bash -c 'hadoop fs -ls $name >/dev/null 2>&1'",
      require => [ Service["hadoop-hdfs-namenode"], Exec["namenode format"] ],
    }
  }

  define namenode ($host = $fqdn , $port = "8020", $thrift_port= "10090", $auth = "simple", $dirs = ["/tmp/nn"]) {

    $hadoop_namenode_host = $host
    $hadoop_namenode_port = $port
    $hadoop_namenode_thrift_port = $thrift_port
    $hadoop_security_authentication = $auth

    include common-hdfs

    package { "hadoop-hdfs-namenode":
      ensure => latest,
      require => Package["jdk"],
    }

    service { "hadoop-hdfs-namenode":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-hdfs-namenode"], File["/etc/hadoop/conf/core-site.xml"], File["/etc/hadoop/conf/hdfs-site.xml"], File["/etc/hadoop/conf/hadoop-env.sh"]],
      require => [Package["hadoop-hdfs-namenode"], Exec["namenode format"]],
    } 

    exec { "namenode format":
      user => "hdfs",
      command => "/bin/bash -c 'yes Y | hadoop namenode -format >> /tmp/nn.format.log 2>&1'",
      creates => "${namenode_data_dirs[0]}/current/VERSION",
      require => [ Package["hadoop-hdfs-namenode"], File[$dirs] ],
    } 
    
    file { $dirs:
      ensure => directory,
      owner => hdfs,
      group => hdfs,
      mode => 700,
      require => [Package["hadoop-hdfs"]], 
    }
  }

  define secondarynamenode ($namenode_host, $namenode_port, $port = "50090", $auth = "simple") {

    $hadoop_secondarynamenode_port = $port
    $hadoop_security_authentication = $auth

    include common-hdfs

    package { "hadoop-hdfs-secondarynamenode":
      ensure => latest,
      require => Package["jdk"],
    }

    service { "hadoop-hdfs-secondarynamenode":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-hdfs-secondarynamenode"], File["/etc/hadoop/conf/core-site.xml"], File["/etc/hadoop/conf/hdfs-site.xml"], File["/etc/hadoop/conf/hadoop-env.sh"]],
      require => [Package["hadoop-hdfs-secondarynamenode"]],
    }
  }


  define resourcemanager ($host = $fqdn, $port = "8040", $rt_port = "8025", $sc_port = "8030", $thrift_port = "9290", $auth = "simple") {
    $hadoop_rm_host = $host
    $hadoop_rm_port = $port
    $hadoop_rt_port = $rt_port
    $hadoop_sc_port = $sc_port
    $hadoop_security_authentication = $auth

    include common-yarn

    package { "hadoop-yarn-resourcemanager":
      ensure => latest,
      require => Package["jdk"],
    }

    service { "hadoop-yarn-resourcemanager":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-yarn-resourcemanager"], File["/etc/hadoop/conf/hadoop-env.sh"], File["/etc/hadoop/conf/yarn-site.xml"]],
      require => [ Package["hadoop-yarn-resourcemanager"] ]
    }
  }

  define historyserver ($host = $fqdn, $port = "10020", $webapp_port = "19888", $auth = "simple") {
    $hadoop_hs_host = $host
    $hadoop_hs_port = $port
    $hadoop_hs_webapp_port = $app_port
    $hadoop_security_authentication = $auth

    include common-mapred-app

    package { "hadoop-mapreduce-historyserver":
      ensure => latest,
      require => Package["jdk"],
    }

    service { "hadoop-mapreduce-historyserver":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-mapreduce-historyserver"], File["/etc/hadoop/conf/hadoop-env.sh"], File["/etc/hadoop/conf/mapred-site.xml"]],
      require => [Package["hadoop-mapreduce-historyserver"]],
    }
  }


  define nodemanager ($rm_host, $rm_port, $rt_port, $auth = "simple", $dirs = ["/tmp/yarn"]){
    $hadoop_rm_host = $rm_host
    $hadoop_rm_port = $rm_port
    $hadoop_rt_port = $rt_port

    include common-yarn

    package { "hadoop-yarn-nodemanager":
      ensure => latest,
      require => Package["jdk"],
    }
 
    service { "hadoop-yarn-nodemanager":
      ensure => running,
      hasstatus => true,
      subscribe => [Package["hadoop-yarn-nodemanager"], File["/etc/hadoop/conf/hadoop-env.sh"], File["/etc/hadoop/conf/yarn-site.xml"]],
      require => [ Package["hadoop-yarn-nodemanager"], File[$dirs] ],
    }

    file { $dirs:
      ensure => directory,
      owner => yarn,
      group => yarn,
      mode => 755,
      require => [Package["hadoop-yarn"]],
    }
  }

  define mapred-app ($namenode_host, $namenode_port, $jobtracker_host, $jobtracker_port, $auth = "simple", $jobhistory_host = "", $jobhistory_port="10020", $dirs = ["/tmp/mr"]){
    $hadoop_namenode_host = $namenode_host
    $hadoop_namenode_port = $namenode_port
    $hadoop_jobtracker_host = $jobtracker_host
    $hadoop_jobtracker_port = $jobtracker_port
    $hadoop_security_authentication = $auth

    include common-mapred-app

    if ($jobhistory_host != "") {
      $hadoop_hs_host = $jobhistory_host
      $hadoop_hs_port = $jobhistory_port
    }

    file { $dirs:
      ensure => directory,
      owner => yarn,
      group => yarn,
      mode => 755,
      require => [Package["hadoop-mapreduce"]],
    }
  }

  define client ($namenode_host, $namenode_port, $jobtracker_host, $jobtracker_port, $auth = "simple") {
      $hadoop_namenode_host = $namenode_host
      $hadoop_namenode_port = $namenode_port
      $hadoop_jobtracker_host = $jobtracker_host
      $hadoop_jobtracker_port = $jobtracker_port
      $hadoop_security_authentication = $auth

      include common-mapred-app
  
      # FIXME: "hadoop-source", "hadoop-fuse", "hadoop-pipes"
      package { ["hadoop-doc", "hadoop-debuginfo", "hadoop-libhdfs"]:
        ensure => latest,
        require => [Package["jdk"], Package["hadoop"], Package["hadoop-hdfs"], Package["hadoop-mapreduce"]],  
      }
  }
}
