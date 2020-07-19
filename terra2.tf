provider "aws" {
	region = "ap-south-1"
	profile = "rajesh"
}

# -- Creating Security Groups

resource "aws_security_group" "sg" {
	name        = "task2-sg"
  	description = "Allow TLS inbound traffic"
  	vpc_id      = "vpc-f6829f9e"


  	ingress {
    		description = "SSH"
    		from_port   = 22
    		to_port     = 22
    		protocol    = "tcp"
    		cidr_blocks = [ "0.0.0.0/0" ]
  	}

  	ingress {
    		description = "HTTP"
    		from_port   = 80
    		to_port     = 80
    		protocol    = "tcp"
    		cidr_blocks = [ "0.0.0.0/0" ]
  	}

  	egress {
    		from_port   = 0
    		to_port     = 0
    		protocol    = "-1"
    		cidr_blocks = ["0.0.0.0/0"]
  	}

  	tags = {
    		Name = "task2-sg"
  	}
}

# -- Creating Ec2 instance

resource "aws_instance" "web_server" {
  	ami = "ami-0447a12f28fddb066"
  	instance_type = "t2.micro"
	  root_block_device {
		volume_type = "gp2"
		delete_on_termination = true
	}
  	key_name = "terrakey"
  	security_groups = [ "${aws_security_group.sg.name}" ]

  	connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = file("/Users/pasupuletirajeshbabu/Downloads/terrakey.pem")
    		host     = aws_instance.web_server.public_ip
  	}

  	provisioner "remote-exec" {
    		inline = [
      			"sudo yum install httpd git -y",
      			"sudo systemctl restart httpd",
      			"sudo systemctl enable httpd",
    		]
  	}

  	tags = {
    		Name = "task2_os"
  	}

}

# -- Creating EFS volume

resource "aws_efs_file_system" "efs" {
   	creation_token = "efs"
   	performance_mode = "generalPurpose"
   	throughput_mode = "bursting"
   	encrypted = "true"
 	tags = {
     	Name = "Efs"
   	}
}

# -- Mounting the EFS volume

resource "aws_efs_mount_target" "efs-mount" {
	depends_on = [
		aws_instance.web_server,
		aws_security_group.sg,
		aws_efs_file_system.efs,
  	]
	
   	file_system_id  = aws_efs_file_system.efs.id
	  subnet_id       = aws_instance.web_server.subnet_id
   	security_groups = ["${aws_security_group.sg.id}"]
	
	
  	connection {
    		type     = "ssh"
    		user     = "ec2-user"
   		private_key = file("/Users/pasupuletirajeshbabu/Downloads/terrakey.pem")
    		host     = aws_instance.web_server.public_ip
  	}

	provisioner "remote-exec" {
    		inline = [
      			"sudo mount ${aws_efs_file_system.efs.id}:/ /var/www/html",
   			    "sudo echo '${aws_efs_file_system.efs.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      			"sudo rm -rf /var/www/html/*",
      			"sudo git clone https://github.com/Pasupuleti-rajesh-babu/AWS_tera.git /var/www/html/"
    		]
	  }
}

# -- Creating S3 Bucket

resource "aws_s3_bucket" "mybucket" {
  bucket = "rajeshbabu666600"
  acl    = "public-read"
  region = "ap-south-1"

  tags = {
    Name = "rajeshbabu666600"
  }
}



# -- Uploading files in S3 bucket

resource "aws_s3_bucket_object" "file_upload" {
	depends_on = [
    		aws_s3_bucket.mybucket,
  	]
  	bucket = "rajeshbabu666600"
  	key    = "efs.jpg"
  	source = "/Users/pasupuletirajeshbabu/Downloads/efs.jpg"
	acl ="public-read"
}

# -- Creating CloudFront

resource "aws_cloudfront_distribution" "s3_distribution" {
	depends_on = [
		aws_efs_mount_target.efs-mount,
    		aws_s3_bucket_object.file_upload,
  	]

	origin {
		domain_name = "${aws_s3_bucket.mybucket.bucket}.s3.amazonaws.com"
		origin_id = "ak" 
        }

	enabled = true
	is_ipv6_enabled = true
	default_root_object = "index.html"

	restrictions {
		geo_restriction {
			restriction_type = "none"
 		 }
 	    }

	default_cache_behavior {
		allowed_methods = ["HEAD", "GET"]
		cached_methods = ["HEAD", "GET"]
		forwarded_values {
			query_string = false
			cookies {
				forward = "none"
			}
		}
		default_ttl = 3600
		max_ttl = 86400
		min_ttl = 0
		target_origin_id = "ak"
		viewer_protocol_policy = "allow-all"
		}

	price_class = "PriceClass_All"

	 viewer_certificate {
   		 cloudfront_default_certificate = true
  	}		
}

# -- Updating cloudfront_url to main lacation 

resource "null_resource" "nullremote3"  {
	depends_on = [
    		aws_cloudfront_distribution.s3_distribution,
  	]

	connection {
    		type     = "ssh"
    		user     = "ec2-user"
   		private_key = file("/Users/pasupuletirajeshbabu/Downloads/terrakey.pem")
    		host     = aws_instance.web_server.public_ip
  	}
	
	provisioner "remote-exec" {
    		inline = [
      "sudo su <<END",
      "echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.file_upload.key}' height='6300' width='1200'>\" >> /var/www/html/index.html",
      "END",
    ]

	}
}

# -- Starting chrome for output

resource "null_resource" "nulllocal1"  {
	depends_on = [
    		null_resource.nullremote3,
  	]

	provisioner "local-exec" {
	    command = "curl ${aws_instance.web_server.public_ip}"
  	}
}
