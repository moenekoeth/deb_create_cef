FROM hashicorp/packer:latest

RUN apk update
RUN apk add docker

RUN mkdir /output/
RUN mkdir /scripts/

COPY builder.pkr.hcl /scripts/
COPY packer.pkr.hcl /scripts/
COPY compiler.pkr.hcl /scripts/
COPY runpacker.sh /scripts/


RUN chmod +x /scripts/runpacker.sh


WORKDIR /scripts/


ENTRYPOINT ["/bin/bash","/scripts/runpacker.sh"]

#CMD ["./runpacker.sh"]
