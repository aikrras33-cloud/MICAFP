import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined
}

// Default to local SQLite for dev/CI; use DATABASE_URL for production Postgres.
const datasourceUrl = process.env.DATABASE_URL ?? 'file:./db/custom.db'

export const db =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: ['query'],
    datasources: { db: { url: datasourceUrl } },
  })

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = db
