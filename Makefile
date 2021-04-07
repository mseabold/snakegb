.PHONY:
all: snake.gb

snake.gb: main.o snake.link
	wlalink -d -S snake.link $@

main.o: main.s
	wla-gb -o $@ $<
