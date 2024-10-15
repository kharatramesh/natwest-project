resource "aws_key_pair" "nkp" {
  key_name   = "natwest-key-pair"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "jenkins" {
  ami                         = "ami-0dee22c13ea7a9a67" # Change to your preferred AMI
  instance_type               = "t3.medium"
  associate_public_ip_address = true # Ensure public IP is assigned
  key_name                    = aws_key_pair.nkp.key_name
  tags = {
    "Name" = "Natwest--jenkins-Vm-Trainer"
  }

  provisioner "file" {
    source      = "ansible.sh"
    destination = "/home/ubuntu/ansible.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod a+x /home/ubuntu/ansible.sh",
      "sudo bash /home/ubuntu/ansible.sh"
    ]
  }
  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = file(pathexpand("~/.ssh/id_rsa"))
    timeout     = "3m"
  }

}
output "PublicIpAddress" {
  value = aws_instance.jenkins.public_ip
}
