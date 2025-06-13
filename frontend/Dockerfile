# SPDX-FileCopyrightText: 2023 Marlon W (Mawoka)
#
# SPDX-License-Identifier: MPL-2.0

### Build Step
# pull the Node.js Docker image
FROM node:19-bullseye as builder

# Create non-root user
RUN useradd -m appuser && \
    chown -R appuser:appuser /usr/src/app

# change working directory
WORKDIR /usr/src/app

# copy the package.json files from local machine to the workdir in container
COPY package*.json ./
COPY pnpm-lock.yaml ./

# install Node.js dependencies
RUN corepack enable && corepack prepare pnpm@8.14.0 --activate && pnpm i

# copy the generated modules and all other files to the container
COPY . .

# build the application
RUN pnpm run build

### Serve Step
# pull the Node.js Docker image
FROM node:19-bullseye-slim

# Create non-root user
RUN useradd -m appuser && \
    chown -R appuser:appuser /app

# change working directory
WORKDIR /app

# copy files from previous step
COPY --from=builder /usr/src/app/package.json .
COPY --from=builder /usr/src/app/pnpm-lock.yaml .
COPY --from=builder /usr/src/app/build .
COPY --from=builder /usr/src/app/node_modules ./node_modules

# expose port 3000
EXPOSE 3000

# switch to non-root user
USER appuser

# start the application
CMD ["pnpm", "run", "run:prod"]
