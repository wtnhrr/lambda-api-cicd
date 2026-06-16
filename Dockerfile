# A AWS mantém essa imagem com o runtime correto para Lambda
FROM public.ecr.aws/lambda/python:3.12

# ARG: variável disponível apenas durante o build da imagem
# Usada para registrar quando o deploy foi feito
ARG DEPLOYED_AT="not set"

# ENV disponível em tempo de execução na Lambda
ENV DEPLOYED_AT=${DEPLOYED_AT}
ENV ENVIRONMENT=production

# Copia o código para o diretório padrão da Lambda na imagem
COPY app/handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
