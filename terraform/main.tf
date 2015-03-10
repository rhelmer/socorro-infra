provider "aws" {
    region = "${var.region}"
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
}

# Once you're in, you're in.
resource "aws_security_group" "private_to_private__any" {
    name = "${var.environment}__private_to_private__any"
    description = "Allow all private traffic."
    ingress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        cidr_blocks = [
            "172.31.0.0/16"
            ]
        }
    ingress {
        from_port = 0
        to_port = 65535
        protocol = "udp"
        cidr_blocks = [
            "172.31.0.0/16"
            ]
        }
    ingress {
        from_port = "-1"
        to_port = "-1"
        protocol = "icmp"
        cidr_blocks = [
            "172.31.0.0/16"
            ]
        }
    tags {
        Environment = "${var.environment}"
    }
}

resource "aws_security_group" "internet_to_any__ssh" {
    name = "${var.environment}__internet_to_any__ssh"
    description = "Allow (alt) SSH to any given node."
    ingress {
        from_port = "${var.alt_ssh_port}"
        to_port = "${var.alt_ssh_port}"
        protocol = "tcp"
        cidr_blocks = [
            "0.0.0.0/0"
        ]
    }
    tags {
        Environment = "${var.environment}"
    }
}

resource "aws_security_group" "internet_to_elb__http" {
    name = "${var.environment}__internet_to_elb__http"
    description = "Allow incoming traffic from Internet to HTTP(S) on ELBs."
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [
            "0.0.0.0/0"
        ]
    }
    tags {
        Environment = "${var.environment}"
    }
}

# symbolapi
resource "aws_security_group" "elb_to_symbolapi__http" {
    name = "${var.environment}__elb_to_symbolapi__http"
    description = "Allow HTTP(S) from ELBs to symbolapi."
    ingress {
        from_port = 8000
        to_port = 8000
        protocol = "tcp"
        security_groups = [
            "${aws_security_group.internet_to_elb__http.id}"
        ]
    }
    tags {
        Environment = "${var.environment}"
    }
}

resource "aws_elb" "elb_for_symbolapi" {
    name = "${var.environment}--elb-for-symbolapi"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    listener {
        instance_port = 8000
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }
    security_groups = [
        "${aws_security_group.internet_to_elb__http.id}"
    ]
}

resource "aws_launch_configuration" "lc_for_symbolapi_asg" {
    name = "${var.environment}__lc_for_symbolapi_asg"
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} symbolapi"
    image_id = "${lookup(var.base_ami, var.region)}"
    instance_type = "c4.xlarge"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    security_groups = [
        "${aws_security_group.internet_to_elb__http.name}",
        "${aws_security_group.elb_to_symbolapi__http.name}",
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
}

resource "aws_autoscaling_group" "asg_for_symbolapi" {
    name = "${var.environment}__asg_for_symbolapi"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    depends_on = [
        "aws_launch_configuration.lc_for_symbolapi_asg"
    ]
    launch_configuration = "${aws_launch_configuration.lc_for_symbolapi_asg.id}"
    max_size = 1
    min_size = 1
    desired_capacity = 1
    load_balancers = [
        "${var.environment}--elb-for-symbolapi"
    ]
}

resource "aws_launch_configuration" "lc_for_consul_asg" {
    name = "${var.environment}__lc_for_consul_asg"
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} consul"
    image_id = "${lookup(var.base_ami, var.region)}"
    instance_type = "t2.micro"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    security_groups = [
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
}

resource "aws_autoscaling_group" "asg_for_consul" {
    name = "${var.environment}__asg_for_consul"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    depends_on = [
        "aws_launch_configuration.lc_for_consul_asg"
    ]
    launch_configuration = "${aws_launch_configuration.lc_for_consul_asg.id}"
    max_size = 5
    min_size = 3
    desired_capacity = 3
    health_check_type = "EC2"
}

# collectors (crash-reports)
resource "aws_security_group" "elb_to_collectors__http" {
    name = "${var.environment}__elb_to_collectors__http"
    description = "Allow HTTP(S) from ELBs to collectors."
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [
            "${aws_security_group.internet_to_elb__http.id}"
        ]
    }
    tags {
        Environment = "${var.environment}"
    }
}

resource "aws_elb" "elb_for_collectors" {
    name = "${var.environment}--elb-for-collectors"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }
    security_groups = [
        "${aws_security_group.internet_to_elb__http.id}"
    ]
}

resource "aws_launch_configuration" "lc_for_collectors_asg" {
    name = "${var.environment}__lc_for_collectors_asg"
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} collectors"
    image_id = "${lookup(var.base_ami, var.region)}"
    instance_type = "c4.xlarge"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    security_groups = [
        "${aws_security_group.internet_to_elb__http.name}",
        "${aws_security_group.elb_to_collectors__http.name}",
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
}

resource "aws_autoscaling_group" "asg_for_collectors" {
    name = "${var.environment}__asg_for_collectors"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    depends_on = [
        "aws_launch_configuration.lc_for_collectors_asg"
    ]
    launch_configuration = "${aws_launch_configuration.lc_for_collectors_asg.id}"
    max_size = 1
    min_size = 1
    desired_capacity = 1
    load_balancers = [
        "${var.environment}--elb-for-collectors"
    ]
}

# webapp (crash-stats)
resource "aws_security_group" "elb_to_webapp__http" {
    name = "${var.environment}__elb_to_webapp__http"
    description = "Allow HTTP(S) from ELBs to webapp."
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [
            "${aws_security_group.internet_to_elb__http.id}"
        ]
    }
    tags {
        Environment = "${var.environment}"
    }
}

resource "aws_elb" "elb_for_webapp" {
    name = "${var.environment}--elb-for-webapp"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }
    security_groups = [
        "${aws_security_group.internet_to_elb__http.id}"
    ]
}

resource "aws_launch_configuration" "lc_for_webapp_asg" {
    name = "${var.environment}__lc_for_webapp_asg"
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} webapp"
    image_id = "${lookup(var.base_ami, var.region)}"
    instance_type = "c4.xlarge"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    security_groups = [
        "${aws_security_group.internet_to_elb__http.name}",
        "${aws_security_group.elb_to_webapp__http.name}",
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
}

resource "aws_autoscaling_group" "asg_for_webapp" {
    name = "${var.environment}__asg_for_webapp"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    depends_on = [
        "aws_launch_configuration.lc_for_webapp_asg"
    ]
    launch_configuration = "${aws_launch_configuration.lc_for_webapp_asg.id}"
    max_size = 1
    min_size = 1
    desired_capacity = 1
    load_balancers = [
        "${var.environment}--elb-for-webapp"
    ]
}

# middleware
resource "aws_security_group" "elb_to_middleware__http" {
    name = "${var.environment}__elb_to_middleware__http"
    description = "Allow HTTP(S) from ELBs to middleware."
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [
            "${aws_security_group.internet_to_elb__http.id}"
        ]
    }
    tags {
        Environment = "${var.environment}"
    }
}

resource "aws_elb" "elb_for_middleware" {
    name = "${var.environment}--elb-for-middleware"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    listener {
        instance_port = 80
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }
    security_groups = [
        "${aws_security_group.internet_to_elb__http.id}"
    ]
}

resource "aws_launch_configuration" "lc_for_middleware_asg" {
    name = "${var.environment}__lc_for_middleware_asg"
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} middleware"
    image_id = "${lookup(var.base_ami, var.region)}"
    instance_type = "c4.xlarge"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    security_groups = [
        "${aws_security_group.internet_to_elb__http.name}",
        "${aws_security_group.elb_to_middleware__http.name}",
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
}

resource "aws_autoscaling_group" "asg_for_middleware" {
    name = "${var.environment}__asg_for_middleware"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    depends_on = [
        "aws_launch_configuration.lc_for_middleware_asg"
    ]
    launch_configuration = "${aws_launch_configuration.lc_for_middleware_asg.id}"
    max_size = 1
    min_size = 1
    desired_capacity = 1
    load_balancers = [
        "${var.environment}--elb-for-middleware"
    ]
}

# processors
resource "aws_launch_configuration" "lc_for_processors_asg" {
    name = "${var.environment}__lc_for_processors_asg"
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} processors"
    image_id = "${lookup(var.base_ami, var.region)}"
    instance_type = "c4.xlarge"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    security_groups = [
        "${aws_security_group.internet_to_elb__http.name}",
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
}

resource "aws_autoscaling_group" "asg_for_processors" {
    name = "${var.environment}__asg_for_processors"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    depends_on = [
        "aws_launch_configuration.lc_for_processors_asg"
    ]
    launch_configuration = "${aws_launch_configuration.lc_for_processors_asg.id}"
    max_size = 1
    min_size = 1
    desired_capacity = 1
    load_balancers = [
        "${var.environment}--elb-for-processors"
    ]
}

# admin (crontabber)
resource "aws_launch_configuration" "lc_for_admin_asg" {
    name = "${var.environment}__lc_for_admin_asg"
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} admin"
    image_id = "${lookup(var.base_ami, var.region)}"
    instance_type = "c4.xlarge"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    security_groups = [
        "${aws_security_group.internet_to_elb__http.name}",
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
}

resource "aws_autoscaling_group" "asg_for_admin" {
    name = "${var.environment}__asg_for_admin"
    availability_zones = [
        "${var.region}a",
        "${var.region}b"
    ]
    depends_on = [
        "aws_launch_configuration.lc_for_admin_asg"
    ]
    launch_configuration = "${aws_launch_configuration.lc_for_admin_asg.id}"
    max_size = 1
    min_size = 1
    desired_capacity = 1
    load_balancers = [
        "${var.environment}--elb-for-admin"
    ]
}

# PostgreSQL
resource "aws_instance" "postgres" {
    ami = "${lookup(var.base_ami, var.region)}"
    instance_type = "t2.micro"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    count = 1
    security_groups = [
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
    block_device {
        device_name = "/dev/sda1"
        delete_on_termination = "${var.del_on_term}"
    }
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} postgres"
    tags {
        Name = "${var.environment}__postgres_${count.index}"
        Environment = "${var.environment}"
    }
}

# Elastic Search
resource "aws_instance" "elasticsearch" {
    ami = "${lookup(var.base_ami, var.region)}"
    instance_type = "t2.micro"
    key_name = "${lookup(var.ssh_key_name, var.region)}"
    count = 1
    security_groups = [
        "${aws_security_group.internet_to_any__ssh.name}",
        "${aws_security_group.private_to_private__any.name}"
    ]
    user_data = "${file(\"socorro_role.sh\")} ${var.puppet_archive} elasticsearch"
    tags {
        Name = "${var.environment}__elasticsearch_${count.index}"
        Environment = "${var.environment}"
    }
}

resource "aws_elb" "elb_for_elasticsearch" {
    name = "${var.environment}--elb-for-elasticsearch"
    availability_zones = [
        "${aws_instance.elasticsearch.*.availability_zone}"
    ]
    listener {
        instance_port = 9200
        instance_protocol = "http"
        lb_port = 9200
        lb_protocol = "http"
    }
    # Sit in front of the elasticsearch.
    instances = [
        "${aws_instance.elasticsearch.*.id}"
    ]
}
