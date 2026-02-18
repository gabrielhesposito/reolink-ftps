#https://github.com/clouddrove/terraform-aws-active-directory/blob/master/examples/Simple-AD/variables.tf#L1C1-L13C2
#need a way for reolink/network to publish IP and keep whitelist open for ad
variable "ip_rules" {
  type = list(object({
    source      = string
    description = string
  }))
  default = [
    {
      source      = "51.79.69.69/32" // change it according to your requirement
      description = "IP Whitelisting"
    }
  ]
  description = "List of IP rules."
}